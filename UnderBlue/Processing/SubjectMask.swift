import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

/// The subject lift (docs/SubjectEmphasis.md). It brightens the subject and follows with its chroma.
///
/// The defaults are the whole recipe. The product is one touch, so these values are the product:
/// nobody tunes them per photo. They were chosen on the five photos in `DeveloperMedia/subjectpicker`
/// and the E1 set, at each photo's own resolution (23 Oct 2026). Tier two at 0.5 read as processed;
/// 0.2 keeps the reef natural and still separates it. Tier three stays under tier two, or the
/// background would lead the foreground.
/// Nil on a plan means no lift, which is what the app ships until E6 turns it on.
struct SubjectLift: Sendable, Equatable {
    var mask: SubjectMask
    /// Lift strength, 0 to 0.9. L becomes `pow(L, 1 - strength)` at mask weight 1, so it cannot
    /// pass white, and the dark part of the subject moves most.
    var strength: Float = 0.18
    /// The most the chroma may grow, whatever `chromaExponent` asks for.
    var chromaCap: Float = 1.3
    /// Tier two: how much of the lift reaches pixels that are not open water but hold no Vision
    /// instance, such as a reef or a wreck. 0 is off, 1 treats them like a Vision subject.
    var tier2: Float = 0.2
    /// Tier three: the same as tier two for the background reef, the part whose contrast the water
    /// has taken. The split and the sharpening's fall come from the plan's water fit
    /// (RestorationEngine.contrastTransmission), so they have no setting here.
    var tier3: Float = 0.1
    /// The highlight pull for tiers two and three. A reef clips where a Vision subject does not.
    var highlights2: Float = 0.85
    var highlights3: Float = 0.85
    /// The lift's weight ramp, read on the mask. Below `maskLow` the lift is off, so it never reaches
    /// the water outside the outline. Equal values leave the mask as Vision built it.
    var maskLow: Float = 0.5
    var maskHigh: Float = 0.8
    /// Clarity inside the subject: the same idea at a wider radius, so it shapes the big forms.
    var clarity: Float = 0.6
    /// The clarity blur radius, as a share of the short side. The scene value is (5 + 3 x haze) / 480.
    var clarityRadius: Float = 6.0 / 480
    /// How much of the subject's highlight range above `highlightKnee` is taken back. 0 is off.
    var highlights: Float = 0.4
    /// Where the highlight pull starts, on OKLab L.
    var highlightKnee: Float = 0.75
    /// Sharpening inside the subject: the pixel's L minus its own small blur, added back. 0 is off.
    var detail: Float = 0.6
    /// The blur radius, as a share of the short side.
    var detailRadius: Float = 2.0 / 480
    /// The high-pass size where the sharpening starts to fade, and where it is off. A strong edge
    /// gets nothing, so an outline grows no halo.
    var detailEdgeLow: Float = 0.05
    var detailEdgeHigh: Float = 0.30
    /// Contrast inside the subject, around `contrastPivot`, on OKLab L. 0 leaves it alone.
    var contrast: Float = 0.15
    /// The L the contrast turns around. A constant, so the kernel keeps no per-frame statistic.
    var contrastPivot: Float = 0.5
    /// Chroma follows `(Lnew / L)` raised to this power. 1/3 is the cube root the first draft used.
    var chromaExponent: Float = 1.0 / 3
    /// Above this L the lift fades out, because the highlight shoulder has already run.
    var highlightStart: Float = 0.85
    /// Below this L the lift fades out, because a dark pixel is mostly noise.
    var noiseFloor: Float = 0.05
    /// Tiers two and three as the picker outlines them. Nil: the kernel splits them from the water share
    /// and the contrast transmission itself, with no depth or texture test.
    var tiers: SubjectTierMap?
}

/// Soft weights for tiers two and three on a grid, row 0 on top: the picker's outline before its 0.5 cut
/// (SubjectTiers). It holds no subject: the lift takes the picked subjects out, so an excluded subject is
/// treated like the scene around it. Built once per photo, with Natural's correction, so a preset change
/// does not move the regions (E25).
struct SubjectTierMap: Sendable, Equatable {
    let width: Int
    let height: Int
    let tier2: [Float]
    let tier3: [Float]

    /// The map as an image over `extent`: red tier two, green tier three.
    func image(matching extent: CGRect) -> CIImage {
        var rgba = [Float](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) { rgba[i * 4] = tier2[i]; rgba[i * 4 + 1] = tier3[i]; rgba[i * 4 + 3] = 1 }
        let data = rgba.withUnsafeBytes { Data($0) }
        let map = CIImage(bitmapData: data, bytesPerRow: width * 4 * MemoryLayout<Float>.size,
                          size: CGSize(width: width, height: height), format: .RGBAf, colorSpace: nil)
        // Row 0 is the top row, as in SubjectMask.image(matching:).
        let scaled = map.transformed(by: CGAffineTransform(scaleX: extent.width / CGFloat(width),
                                                           y: extent.height / CGFloat(height)))
        return scaled.transformed(by: CGAffineTransform(translationX: extent.minX - scaled.extent.minX,
                                                        y: extent.minY - scaled.extent.minY))
    }
}

/// The photo's main subjects (Vision foreground instances, all of them) as a soft mask:
/// 0 is background, 1 is subject. Row 0 is the top row, as in NormalizedDepthMap.
///
/// The local veil measures the broad light around each pixel (RestorationEngine.restore). A bright
/// subject raised that light for the water beside it, so the veil took too much there and the water
/// around the subject turned into a dark band (O4 manta, 1 Oct 2026: band against the water above,
/// lightness -0.032; the source +0.005). With the mask, that light leaves the subject out.
struct SubjectMask: Sendable, Equatable {
    let width: Int
    let height: Int
    let values: [Float]

    /// A larger mask is a reef or a scene, not a subject (m5: the reef block was 31% of the frame).
    /// This is the local veil's cap. The subject lift uses `liftMaximumShare`.
    static let maximumShare: Float = 0.25
    /// The cap for the subject lift. Lifting a large subject is safe; taking the veil off one is not.
    /// m5's coral block (31%) is the photo's subject, so the veil cap rejected it (docs/SubjectEmphasis.md, E2).
    /// 0.5 matches `SubjectCandidates.maximumPickedShare`. Above half the frame it is a scene, not a subject.
    static let liftMaximumShare: Float = 0.5
    /// Below this the mask is noise.
    static let minimumShare: Float = 0.005
    /// Vision reads a small image; the mask is made at this long side.
    static let side: CGFloat = 1024

    /// Nil when Vision finds no subject, or the subjects cover too little or too much of the frame.
    /// `cap` is the largest share the caller accepts. The default is the local veil's cap.
    static func estimate(_ image: CIImage, cap: Float = maximumShare) -> SubjectMask? {
        guard let input = visionInput(image) else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: input, options: [:])
        guard (try? handler.perform([request])) != nil, let observation = request.results?.first,
              !observation.allInstances.isEmpty,
              let buffer = try? observation.generateMask(forInstances: observation.allInstances),
              let mask = grid(buffer, extent: image.extent)
        else { return nil }
        let share = mask.values.reduce(0, +) / Float(mask.values.count)
        guard share >= minimumShare, share <= cap else { return nil }
        return mask
    }

    /// The precise mask's long side. Its source is full size, so 1024 would blur finger gaps on a 48 MP photo.
    static let preciseSide: CGFloat = 2048

    /// The foreground mask refined by Vision's iterative segmentation, for one photo at a time (E24).
    /// The foreground instances give the seed box; the segmentation then follows the photo's own edges at
    /// full size, so water between fingers and inside a hose loop leaves the mask. The full-size result is
    /// scaled down on the GPU, so no full-size array is built. Nil when either request fails or the
    /// share is out of range; the caller then uses `estimate`. `precise` does the segmentation.
    @available(iOS 27.0, macOS 27.0, *)
    static func estimatePrecise(_ image: CIImage, cap: Float = maximumShare, context: CIContext) async -> SubjectMask? {
        guard let input = visionInput(image),
              let instances = try? await GenerateForegroundInstanceMaskRequest().perform(on: input),
              !instances.allInstances.isEmpty,
              let coarse = try? instances.generateMask(for: instances.allInstances),
              let box = seedBox(coarse),
              let mask = await precise(image, box: box, context: context) else { return nil }
        let share = mask.values.reduce(0, +) / Float(mask.values.count)
        guard share >= minimumShare, share <= cap else { return nil }
        return mask
    }

    /// Whether the segmentation model is on the device: notReady, downloading, ready or an error. Apple
    /// downloads it once into the system's shared assets, not into the app (54 MB on a Mac, E24).
    @available(iOS 27.0, macOS 27.0, *)
    static func preciseModelStatus() async -> DownloadableAssetsRequestStatus {
        await GenerateIterativeSegmentationRequest(seedPoint: NormalizedPoint(x: 0.5, y: 0.5)).assetStatus
    }

    /// Whether the model is usable now, found by one segmentation on a small grey image. Call it before
    /// `downloadPreciseModel`: `assetStatus` reads notReady in every new process, but a model already on the
    /// device runs without the download call (Mac: 3.3 s on the first call of a process, then 167 ms), so this
    /// needs no network. On the iPhone in airplane mode the download call never finished (24 Oct 2026, E25).
    @available(iOS 27.0, macOS 27.0, *)
    static func preciseModelUsable() async -> Bool {
        let probe = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.6)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        let request = GenerateIterativeSegmentationRequest(seedBox: NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        request.qualityLevel = .accurate
        guard (try? await request.perform(on: probe)) != nil else { return false }
        if case .ready = await request.assetStatus { return true }
        return false
    }

    /// Downloads the segmentation model, reporting to `progress`. Throws on no network or a failed download.
    @available(iOS 27.0, macOS 27.0, *)
    static func downloadPreciseModel(progress: consuming Subprogress) async throws {
        try await GenerateIterativeSegmentationRequest(seedPoint: NormalizedPoint(x: 0.5, y: 0.5)).downloadAssets(progress: progress)
    }

    /// The iterative segmentation seeded with one box (Vision's normalized space, origin at the bottom left),
    /// on the `preciseSide` grid, with no share test. The picker calls it once per group box.
    @available(iOS 27.0, macOS 27.0, *)
    static func precise(_ image: CIImage, box: NormalizedRect, context: CIContext) async -> SubjectMask? {
        guard let input = visionInput(image) else { return nil }
        let request = GenerateIterativeSegmentationRequest(seedBox: box)
        request.qualityLevel = .accurate
        // Never download here: a preview would wait on the network, and fail without one. The UI starts the
        // download (downloadPreciseModel) when the user turns Labs on; until it is ready this returns nil
        // and the photo gets no lift, never the old 512 mask (E23).
        guard case .ready = await request.assetStatus,
              let observation = try? await request.perform(on: input) else { return nil }
        let extent = input.extent
        let scale = min(1, preciseSide / max(extent.width, extent.height))
        let width = max(2, Int((extent.width * scale).rounded(.down))), height = max(2, Int((extent.height * scale).rounded(.down)))
        var values = [Float](repeating: 0, count: width * height)
        observation.pixelBuffer.withUnsafeBuffer { buffer in
            let full = CIImage(cvPixelBuffer: buffer)
            let resample = CIFilter.lanczosScaleTransform()
            resample.inputImage = full
            resample.scale = Float(CGFloat(width) / full.extent.width)
            resample.aspectRatio = Float((CGFloat(height) / full.extent.height) / (CGFloat(width) / full.extent.width))
            let small = resample.outputImage ?? full
            // render(toBitmap:) writes the top row first, which is the mask's row 0, so no flip.
            values.withUnsafeMutableBytes { raw in
                context.render(small, toBitmap: raw.baseAddress!, rowBytes: width * MemoryLayout<Float>.size,
                               bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .Rf, colorSpace: nil)
            }
        }
        for i in values.indices { values[i] = values[i].isFinite ? min(1, max(0, values[i])) : 0 }
        return SubjectMask(width: width, height: height, values: values)
    }

    /// The box around the coarse mask's values above 0.5, in Vision's normalized space (origin at the bottom left).
    @available(iOS 27.0, macOS 27.0, *)
    private static func seedBox(_ buffer: CVPixelBuffer) -> NormalizedRect? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer), row = CVPixelBufferGetBytesPerRow(buffer)
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent32Float,
              let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        var minX = w, maxX = -1, minY = h, maxY = -1
        for y in 0..<h {
            let line = (base + y * row).assumingMemoryBound(to: Float.self)
            for x in 0..<w where line[x] > 0.5 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return NormalizedRect(x: CGFloat(minX) / CGFloat(w), y: 1 - CGFloat(maxY + 1) / CGFloat(h),
                              width: CGFloat(maxX - minX + 1) / CGFloat(w), height: CGFloat(maxY - minY + 1) / CGFloat(h))
    }

    /// The image Vision reads: the whole image, moved to the origin. Nil for an empty or infinite extent.
    /// Vision scales it to its own model size (512 x 512) by itself. A copy we scaled first was read
    /// twice: r14 lost its mask at 1024 x 767 and kept it at 1024 x 768, and DSC03545 the other way
    /// round. From the whole image both keep it, at every input size, on the Mac and the iPhone
    /// (docs/SubjectEmphasis.md, E21). It is also faster: no full-size scale pass before Vision.
    static func visionInput(_ image: CIImage) -> CIImage? {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0, extent.width.isFinite, extent.height.isFinite else { return nil }
        return image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
    }

    /// Vision's mask at its model size, which is the frame stretched to a square, resampled
    /// (bilinear) to `side` at the frame's aspect. It never builds a mask at the photo's own size.
    /// Nil when the buffer is not one float per pixel.
    static func grid(_ buffer: CVPixelBuffer, extent: CGRect) -> SubjectMask? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let sourceWidth = CVPixelBufferGetWidth(buffer), sourceHeight = CVPixelBufferGetHeight(buffer)
        let row = CVPixelBufferGetBytesPerRow(buffer)
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent32Float,
              sourceWidth > 1, sourceHeight > 1, let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        var source = [Float](repeating: 0, count: sourceWidth * sourceHeight)
        for y in 0..<sourceHeight {
            let line = (base + y * row).assumingMemoryBound(to: Float.self)
            for x in 0..<sourceWidth { source[y * sourceWidth + x] = line[x].isFinite ? min(1, max(0, line[x])) : 0 }
        }
        let scale = min(1, side / max(extent.width, extent.height))
        let width = max(2, Int((extent.width * scale).rounded(.down))), height = max(2, Int((extent.height * scale).rounded(.down)))
        // Sample positions on the source grid, pixel centres to pixel centres.
        func taps(_ count: Int, _ sourceCount: Int) -> [(Int, Int, Float)] {
            (0..<count).map { i in
                let p = max(0, (Float(i) + 0.5) * Float(sourceCount) / Float(count) - 0.5)
                let low = min(sourceCount - 1, Int(p))
                return (low, min(sourceCount - 1, low + 1), p - Float(low))
            }
        }
        let columns = taps(width, sourceWidth), rows = taps(height, sourceHeight)
        var values = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            let (y0, y1, fy) = rows[y]
            for x in 0..<width {
                let (x0, x1, fx) = columns[x]
                let top = source[y0 * sourceWidth + x0] * (1 - fx) + source[y0 * sourceWidth + x1] * fx
                let bottom = source[y1 * sourceWidth + x0] * (1 - fx) + source[y1 * sourceWidth + x1] * fx
                values[y * width + x] = top * (1 - fy) + bottom * fy
            }
        }
        return SubjectMask(width: width, height: height, values: values)
    }

    /// The mask as an image over `extent` (red holds the mask).
    func image(matching extent: CGRect) -> CIImage {
        let data = values.withUnsafeBytes { Data($0) }
        let mask = CIImage(bitmapData: data, bytesPerRow: width * MemoryLayout<Float>.size,
                           size: CGSize(width: width, height: height), format: .Rf, colorSpace: nil)
        let scaled = mask.transformed(by: CGAffineTransform(scaleX: extent.width / CGFloat(width),
                                                            y: extent.height / CGFloat(height)))
        return scaled.transformed(by: CGAffineTransform(translationX: extent.minX - scaled.extent.minX,
                                                        y: extent.minY - scaled.extent.minY))
    }
}
