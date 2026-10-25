import CoreImage
import ImageIO
import Vision
import UniformTypeIdentifiers
import os

enum PhotoPipelineVariant: String, CaseIterable, Sendable {
    case original, current, restoration, combined

    #if DEBUG
    static var selected: Self {
        let prefix = "--photo-pipeline="
        guard let value = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) })?.dropFirst(prefix.count),
              let variant = Self(rawValue: String(value)) else { return .combined }
        return variant
    }
    #endif
}

/// The precise model is not on the device yet (PreciseModelLoader). The picker waits, and there is no lift.
enum SubjectModelError: Error, Equatable { case notReady }

actor PhotoProcessor {
    let engine = FilterEngine()
    private let diagnostics: DiagnosticRecorder?
    private let depthEstimator = DepthEstimator()
    private let waterEstimator = WaterModelEstimator()
    private let restorationEngine = RestorationEngine()
    private let photoHDR = PhotoHDR()
    private struct Prepared { let analysis: WaterAnalysis; let plan: RestorationPlan? }
    /// Keyed by photo so a batch can switch between photos without repeating depth analysis.
    private var prepared: [URL: Prepared] = [:]
    /// The pickable subject groups per photo. Made on the first request, because Vision runs again for them.
    /// A photo with no subject is stored as nil, so it is not tried twice.
    private var candidates: [URL: SubjectCandidates?] = [:]
    /// Tier maps per photo, nil when a photo has none. Made once: they do not follow the preset.
    private var tierMaps: [URL: SubjectTiers?] = [:]
    private var recordedRenderFallback = false
    private var recordedKernelFallback = false
    #if DEBUG
    private let logger = Logger(subsystem: "com.underblue.app", category: "photo-restoration")
    #endif

    init(diagnostics: DiagnosticRecorder? = nil) {
        self.diagnostics = diagnostics
    }

    func open(_ url: URL) throws -> CIImage {
        if UTType(filenameExtension: url.pathExtension)?.conforms(to: .rawImage) == true { return try openRAW(url) }
        guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true, .expandToHDR: true]),
              image.extent.width > 0, image.extent.height > 0 else { throw UnderBlueError.unreadable }
        return image
    }
    /// Camera RAW needs CIRAWFilter. On iOS, CIImage(contentsOf:) returned only the small embedded
    /// preview (1616 px long side for a 5472 px Sony ARW). The filter's default output is Apple's standard
    /// SDR rendering, upright. A RAW this device can't decode is reported as unsupported, not exported small.
    private func openRAW(_ url: URL) throws -> CIImage {
        guard let image = CIRAWFilter(imageURL: url)?.outputImage, image.extent.width > 0, image.extent.height > 0 else {
            throw UnderBlueError.unsupported
        }
        return image
    }

    /// The image Vision reads. For a RAW it is the camera's embedded preview, upright. Only the subject
    /// search uses it. The colour correction still runs on the neutral RAW rendering. The masks are in
    /// 0 to 1 coordinates, so the smaller size does not matter. On the RAW rendering Vision found the
    /// two white fish on DSC03545 and lost the divers, at every size tried. On the preview it found
    /// the divers, as on the camera's JPEG: share 0.0252 against 0.0255. The size was not the cause:
    /// the JPEG at 1616 px gave 0.0248 (24 Oct 2026).
    private func visionImage(_ url: URL, source: CIImage) throws -> CIImage {
        guard UTType(filenameExtension: url.pathExtension)?.conforms(to: .rawImage) == true,
              let filter = CIRAWFilter(imageURL: url), let preview = filter.previewImage,
              preview.extent.width > 0, preview.extent.height > 0 else { return source }
        let upright = preview.oriented(filter.orientation)
        // A preview with another shape is a crop or a thumbnail strip. Its masks would not line up.
        let a = upright.extent.width / upright.extent.height, b = source.extent.width / source.extent.height
        guard abs(a - b) / b < 0.02 else { return source }
        return engine.sdr(upright)
    }

    func analyze(_ url: URL) async throws -> WaterAnalysis {
        let source = engine.sdr(try open(url))
        return try await prepare(url: url, source: source).analysis
    }
    /// The groups the user can pick from, or nil when Vision finds no usable subject.
    func subjectCandidates(_ url: URL) async throws -> SubjectCandidates? {
        if let known = candidates[url] { return known }
        try Task.checkCancellation()
        // On 27 the groups need the precise model. Until it is on the device the picker waits and there is
        // no lift. Nothing is cached, so the next call after the download builds the groups.
        if #available(iOS 27, macOS 27, *) {
            guard case .ready = await SubjectMask.preciseModelStatus() else { throw SubjectModelError.notReady }
        }
        let seen = try visionImage(url, source: engine.sdr(try open(url)))
        var found = SubjectCandidates.estimate(seen)
        if #available(iOS 27, macOS 27, *), let coarse = found { found = await precise(coarse, image: seen) }
        candidates[url] = .some(found)
        return found
    }

    /// Each group's mask from the precise segmentation, seeded by the group's box. Manual picking only
    /// makes sense with the precise mask (Jake, 24 Oct 2026). A group whose segmentation fails is left out.
    /// The coarse mask is never used instead: its lift is the one Jake rejected (E23). Nil when every
    /// group fails. A neighbour inside a group's box was not pulled in on r07 and aquafix_20
    /// (subject-lift session, 24 Oct 2026).
    @available(iOS 27, macOS 27, *)
    private func precise(_ coarse: SubjectCandidates, image: CIImage) async -> SubjectCandidates? {
        var kept: [SubjectGroup] = [], masks: [SubjectMask] = []
        for group in coarse.groups {
            let b = group.bounds
            // Vision's normalized space has its origin at the bottom left.
            let box = NormalizedRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
            guard let mask = await SubjectMask.precise(image, box: box, context: engine.context) else { continue }
            kept.append(group); masks.append(mask)
        }
        guard !kept.isEmpty else { return nil }
        return SubjectCandidates(width: coarse.width, height: coarse.height, groups: kept, merged: coarse.merged)
            .replacingMasks(masks)
    }

    /// Manual mode: the subject under a press at `point` (0...1, top left origin), on the image Vision reads,
    /// so its grid matches the Semi-auto groups. One request with the seed alone, so the added-points trap does
    /// not apply (docs/ManualSubject.md). About 0.1-0.25 s on an iPhone 17 (R8). Nil when nothing is found.
    func pressMask(_ url: URL, at point: CGPoint) async throws -> SubjectMask? {
        try Task.checkCancellation()
        guard #available(iOS 27, macOS 27, *) else { return nil }
        guard case .ready = await SubjectMask.preciseModelStatus() else { throw SubjectModelError.notReady }
        let seen = try visionImage(url, source: engine.sdr(try open(url)))
        let seed = NormalizedPoint(x: min(1, max(0, point.x)), y: 1 - min(1, max(0, point.y)))
        guard let mask = await SubjectMask.precise(seen, point: seed, context: engine.context),
              mask.values.contains(where: { $0 > 0.5 }) else { return nil }
        return mask
    }
    /// Tiers two and three on the candidates' grid: the soft map the lift reads and the picker's outline.
    /// Nil without a plan (no depth fit), or when no region is left. Made once per photo with Natural's
    /// correction, so a preset change does not move the regions. Preview and export make the same map.
    func subjectTiers(_ url: URL) async throws -> SubjectTiers? {
        if let known = tierMaps[url] { return known }
        try Task.checkCancellation()
        let source = engine.sdr(try open(url))
        let prepared = try await prepare(url: url, source: source)
        guard let plan = prepared.plan else { tierMaps[url] = .some(nil); return nil }
        let settings = FilterSettings(preset: .natural, intensity: FilterSettings.defaultIntensity,
                                      analysis: prepared.analysis, adjustments: .zero)
        // A fixed grid: the precise groups are on a 2048 grid, and the CPU work grows with the area.
        let long = max(source.extent.width, source.extent.height)
        let width = Int((source.extent.width / long * CGFloat(SubjectCandidates.drawingSide)).rounded())
        let height = Int((source.extent.height / long * CGFloat(SubjectCandidates.drawingSide)).rounded())
        guard width > 1, height > 1 else { return nil }
        let small = source.transformed(by: CGAffineTransform(scaleX: CGFloat(width) / source.extent.width,
                                                             y: CGFloat(height) / source.extent.height))
        let current = restorationEngine.corrections(settings: settings, plan: plan).current
        guard let share = engine.waterShare(small, correction: current),
              let transmission = restorationEngine.contrastTransmission(small, plan: plan) else { return nil }
        // The share is in alpha. Red holds luminance times the share (UnderBlueCalmShare).
        let shareValues = SubjectTiers.channel(share, 3, width: width, height: height, context: engine.context)
        let tValues = SubjectTiers.channel(transmission, 0, width: width, height: height, context: engine.context)
        let map = plan.depth
        let depthData = map.values.withUnsafeBytes { Data($0) }
        let depthImage = CIImage(bitmapData: depthData, bytesPerRow: map.width * MemoryLayout<Float>.size,
                                 size: CGSize(width: map.width, height: map.height), format: .Rf, colorSpace: nil)
        let depthValues = SubjectTiers.channel(depthImage, 0, width: width, height: height, context: engine.context)
        let c = engine.context
        let red = SubjectTiers.channel(small, 0, width: width, height: height, context: c)
        let green = SubjectTiers.channel(small, 1, width: width, height: height, context: c)
        let blue = SubjectTiers.channel(small, 2, width: width, height: height, context: c)
        let luma = (0..<(width * height)).map { i in pow(max(0, 0.2126 * red[i] + 0.7152 * green[i] + 0.0722 * blue[i]), 1 / 2.2) }
        let made = SubjectTiers.make(waterShare: shareValues, transmission: tValues, depth: depthValues,
                                     texture: SubjectTiers.texture(luma: luma, width: width, height: height),
                                     width: width, height: height)
        let tiers = made?.isEmpty == false ? made : nil
        tierMaps[url] = .some(tiers)
        return tiers
    }

    /// The plan for a subject choice, with the tier map on the lift when the lift is on.
    private func plan(for url: URL, source: CIImage, subjects: SubjectChoice) async throws -> RestorationPlan? {
        let base = try await prepare(url: url, source: source).plan
        let auto = subjects == .auto ? try await autoLiftMask(url) : nil
        var plan = Self.applying(subjects, to: base, autoLift: auto)
        if plan?.subjectLift != nil, let tiers = try await subjectTiers(url) {
            var off: Set<Int> = []
            if case .picked(_, let tiersOff, _) = subjects { off = tiersOff }
            // The same pieces as the picker: outside every group. Preview and export build them alike.
            var pieces: SubjectTiers.Pieces?
            if !off.isEmpty, let found = try? await subjectCandidates(url) {
                pieces = tiers.pieces(excluding: found.mask(picking: Set(found.groups.map(\.id))))
            }
            plan?.subjectLift?.tiers = tiers.map(excluding: off, pieces: pieces)
        }
        return plan
    }
    func preview(_ url: URL, settings: FilterSettings, original: Bool, maxPixel: CGFloat = 1600,
                 subjects: SubjectChoice = .off) async throws -> CGImage {
        try Task.checkCancellation()
        let source = engine.sdr(try open(url))
        let plan = original ? nil : try await plan(for: url, source: source, subjects: subjects)
        let ratio = min(1, maxPixel / max(source.extent.width, source.extent.height))
        let small = source.transformed(by: CGAffineTransform(scaleX: ratio, y: ratio))
        let chosen = Self.settings(settings, for: subjects) { engine.analyze(source, subjects: $0) }
        let result = original ? small : processed(small, settings: chosen, plan: plan)
        guard let rendered = engine.context.createCGImage(result, from: result.extent, format: .RGBA8, colorSpace: FilterEngine.photoSpace) else { throw UnderBlueError.unreadable }
        return rendered
    }
    /// Headroom above SDR white. Above 1, the photo can export as HDR. RAW opens as SDR.
    func headroom(_ url: URL) throws -> Float { try open(url).contentHeadroom }

    /// `keepHDR` adds a gain map when the source is HDR. SDR sources always export SDR.
    /// Quality is 1 in both formats. Below it, ImageIO wrote JPEG with half-resolution colour (4:2:0).
    /// In both formats, quality 0.95 to 0.99 barely changed the error (measured 28 Sep 2026).
    /// A JPEG source is already compressed, so each save must add as little loss as possible.
    func export(_ url: URL, settings: FilterSettings, keepHDR: Bool = false,
                format: ExportOptions.PhotoFormat = .jpeg, subjects: SubjectChoice = .off) async throws -> URL {
        try Task.checkCancellation()
        let original = try open(url)
        let source = engine.sdr(original)
        let plan = try await plan(for: url, source: source, subjects: subjects)
        let chosen = Self.settings(settings, for: subjects) { engine.analyze(source, subjects: $0) }
        let image = processed(source, settings: chosen, plan: plan)
        // The SDR image in the file is the normal export. The HDR version (PhotoHDR) becomes its gain map.
        var hdr: CIImage?
        if keepHDR, original.contentHeadroom > 1 {
            guard let expanded = photoHDR.reexpand(image, original: original, toneMapped: source) else { throw UnderBlueError.exportFailed }
            hdr = expanded
        }
        let target = try TemporaryFiles.makeURL(extension: format.fileExtension)
        do {
            var options: [CIImageRepresentationOption: Any] = [Self.quality: 1.0]
            if let hdr { options[.hdrImage] = hdr }
            let tagged = image.settingProperties(Self.metadata(from: url))
            switch format {
            case .jpeg:
                try engine.context.writeJPEGRepresentation(of: tagged, to: target, colorSpace: FilterEngine.photoSpace, options: options)
            case .heic:
                try engine.context.writeHEIF10Representation(of: tagged, to: target, colorSpace: FilterEngine.photoSpace, options: options)
            }
            try Task.checkCancellation()
            try Self.check(target, format: format, size: image.extent.size, hdr: hdr != nil)
            return target
        } catch { TemporaryFiles.remove(target); throw error }
    }

    private static let quality = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)

    /// A file reaches the user only if it opens at full size in the chosen format. HEIC must hold 10 bits,
    /// and an HDR export its gain map with headroom above SDR white.
    private static func check(_ url: URL, format: ExportOptions.PhotoFormat, size: CGSize, hdr: Bool) throws {
        guard let file = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(file) == 1,
              CGImageSourceGetType(file) as String? == format.type.identifier,
              let decoded = CGImageSourceCreateImageAtIndex(file, 0, nil),
              decoded.width == Int(size.width.rounded()), decoded.height == Int(size.height.rounded()),
              format == .jpeg || (CGImageSourceCopyPropertiesAtIndex(file, 0, nil) as? [CFString: Any])?[kCGImagePropertyDepth] as? Int == 10
        else { throw UnderBlueError.invalidOutput }
        guard hdr else { return }
        guard CGImageSourceCopyAuxiliaryDataInfoAtIndex(file, 0, kCGImageAuxiliaryDataTypeISOGainMap) != nil,
              let expanded = CIImage(contentsOf: url, options: [.expandToHDR: true]), expanded.contentHeadroom > 1
        else { throw UnderBlueError.invalidOutput }
    }

    /// Orientation is baked into the pixels. Only the capture dates are kept: no stale thumbnails,
    /// dimensions or source gain maps.
    private static func metadata(from url: URL) -> [CFString: Any] {
        var properties: [CFString: Any] = [kCGImagePropertyOrientation: 1]
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let original = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let exif = original[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            var dates: [CFString: Any] = [:]
            for key in [kCGImagePropertyExifDateTimeOriginal, kCGImagePropertyExifDateTimeDigitized] { dates[key] = exif[key] }
            properties[kCGImagePropertyExifDictionary] = dates
        }
        return properties
    }

    #if DEBUG
    /// LLDB/tests can render all four variants without adding temporary production UI.
    func comparisonPreviews(_ url: URL, settings: FilterSettings) async throws -> [PhotoPipelineVariant: CGImage] {
        let source = engine.sdr(try open(url))
        let plan = try await prepare(url: url, source: source).plan
        let ratio = min(1, 1600 / max(source.extent.width, source.extent.height))
        let small = source.transformed(by: CGAffineTransform(scaleX: ratio, y: ratio))
        var result: [PhotoPipelineVariant: CGImage] = [:]
        for variant in PhotoPipelineVariant.allCases {
            let image = processed(small, settings: settings, plan: plan, debugVariant: variant)
            if let rendered = engine.context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: FilterEngine.photoSpace) {
                result[variant] = rendered
            }
        }
        return result
    }
    #endif

    /// Drops a photo's cached analysis once it leaves the session.
    func forget(_ url: URL) { prepared[url] = nil; candidates[url] = nil; tierMaps[url] = nil }

    /// The white reference trusts what sits on a subject (FilterEngine.analyze). With picked subjects it
    /// reads the picks, so a group the user cleared is not a subject there either (Jake, 24 Oct 2026).
    /// `analyze` measures the photo with a mask. It samples 48 px, so it is cheap. Auto keeps the
    /// caller's analysis, which `prepare` made with the automatic mask.
    static func settings(_ settings: FilterSettings, for choice: SubjectChoice,
                         analyze: (SubjectMask?) -> WaterAnalysis) -> FilterSettings {
        guard case .picked(let mask, _, _) = choice else { return settings }
        var chosen = settings
        chosen.analysis = analyze(mask)
        return chosen
    }

    /// The one place a subject choice meets the plan, so preview and export get the same mask.
    /// A photo with no mask is not routed differently (liftDark is for video only).
    /// The lift is a Labs feature for 27 (Jake, 24 Oct 2026). Off: no lift, and the veil keeps the automatic
    /// mask, as main ships. Auto: the lift on `autoLift`, all the groups. Picked: the picks for the veil and the lift,
    /// at the user's strength. Strength 0 keeps the picks for the veil and drops the lift.
    static func applying(_ choice: SubjectChoice, to plan: RestorationPlan?, autoLift: SubjectMask? = nil) -> RestorationPlan? {
        guard var plan else { return nil }
        switch choice {
        case .off: plan.subjectLift = nil
        case .auto: plan.subjectLift = autoLift.map { SubjectLift(mask: $0) }
        case .picked(let mask, _, let strength):
            plan.subjectMask = mask
            plan.subjectLift = mask.flatMap { SubjectLift(mask: $0).scaled(strength) }
        }
        return plan
    }

    /// Auto's lift mask: every group, precise on 27, so Auto looks like Manual with all groups picked.
    /// It takes the lift's cap: the veil's 0.25 rejects a reef that is the photo's subject (E2).
    private func autoLiftMask(_ url: URL) async throws -> SubjectMask? {
        #if DEBUG
        // UB_NO_LIFT runs the photo path with no lift, as the control for a device check.
        if ProcessInfo.processInfo.environment["UB_NO_LIFT"] != nil { return nil }
        #endif
        let found: SubjectCandidates?
        do { found = try await subjectCandidates(url) } catch SubjectModelError.notReady { return nil }
        guard let found, let all = found.mask(picking: Set(found.groups.map(\.id))) else { return nil }
        let share = all.values.reduce(0, +) / Float(all.values.count)
        return share >= SubjectMask.minimumShare && share <= SubjectMask.liftMaximumShare ? all : nil
    }

    private func prepare(url: URL, source: CIImage) async throws -> Prepared {
        if let cached = prepared[url] { return cached }
        // The mask comes first: the white reference trusts what sits on a subject (FilterEngine.analyze).
        let seen = try visionImage(url, source: source)
        let subjects = SubjectMask.estimate(seen)
        let analysis = engine.analyze(source, subjects: subjects)
        #if DEBUG
        logger.debug("current values(natural): \(ColorCorrection.make(analysis: analysis, preset: .natural).logDescription, privacy: .public)")
        #endif
        if let diagnostics {
            // A real measurement never equals .neutral; it means no usable pixels were found.
            if analysis == .neutral {
                await diagnostics.record(.restorationFallback(.photoNoUsablePixels), operation: .photoRestoration)
            }
            // A missing finishing kernel silently weakens every output, so report it once per processor.
            if !engine.finishingKernelAvailable, !recordedKernelFallback {
                recordedKernelFallback = true
                await diagnostics.record(.restorationFallback(.finishKernel), operation: .photoRestoration)
            }
        }
        recordedRenderFallback = false
        var restorationPlan: RestorationPlan?
        do {
            let depth = try await depthEstimator.estimate(image: source, sourceURL: url)
            try Task.checkCancellation()
            var plan = try waterEstimator.estimate(image: source, depth: depth, legacy: analysis, context: engine.context)
            plan.subjectMask = subjects
            restorationPlan = plan
            #if DEBUG
            logger.debug("Binf=(\(plan.backscatterInfinity.x),\(plan.backscatterInfinity.y),\(plan.backscatterInfinity.z)) betaD=(\(plan.betaDirect.x),\(plan.betaDirect.y),\(plan.betaDirect.z)) betaB=(\(plan.betaBackscatter.x),\(plan.betaBackscatter.y),\(plan.betaBackscatter.z)) confidence=\(plan.confidence) floorPixels=\(plan.transmissionFloorPixelPercentage)% maxGainPixels=\(plan.maximumGainPixelPercentage)%")
            logger.debug("restored values(natural): \(ColorCorrection.make(analysis: analysis, preset: .natural, plan: plan).logDescription, privacy: .public)")
            #endif
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Depth/model/fitting failures deliberately preserve the shipping UnderBlue result.
            if let diagnostics {
                let failure = (error as? RestorationError).map { Failure.restorationFallback(.photoAnalysis, cause: $0) }
                    ?? .restorationFallback(.photoAnalysis)
                await diagnostics.record(failure, operation: .photoRestoration)
            }
            #if DEBUG
            logger.debug("Depth-aware restoration unavailable; using current UnderBlue correction")
            #endif
        }
        let result = Prepared(analysis: analysis, plan: restorationPlan)
        prepared[url] = result
        return result
    }

    private func processed(_ source: CIImage, settings: FilterSettings, plan: RestorationPlan?,
                           debugVariant: PhotoPipelineVariant? = nil) -> CIImage {
        let current = engine.apply(source, settings: settings)
        #if DEBUG
        let variant = debugVariant ?? PhotoPipelineVariant.selected
        #else
        let variant = PhotoPipelineVariant.combined
        #endif
        if variant == .original { return source }
        if variant == .current { return current }
        guard let plan else { return current }
        do {
            if variant == .restoration {
                return engine.blend(source, try restorationEngine.restore(source, plan: plan), amount: plan.confidence)
            }
            // The one colour entry point shared with video preview and export. Low-confidence fits
            // approach the exact existing UnderBlue output.
            return try restorationEngine.combined(source, plan: plan, settings: settings, filter: engine,
                                                  subjectLift: plan.subjectLift)
        } catch {
            if !recordedRenderFallback, let diagnostics {
                recordedRenderFallback = true
                Task { await diagnostics.record(.restorationFallback(.photoRender), operation: .photoRestoration) }
            }
            #if DEBUG
            logger.debug("Restoration render failed; using current UnderBlue correction")
            #endif
            return current
        }
    }
}
