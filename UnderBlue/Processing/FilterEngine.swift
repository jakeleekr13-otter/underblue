import CoreImage
import CoreImage.CIFilterBuiltins
import Metal
import simd

final class FilterEngine: Sendable {
    // CIContext is thread safe. CIFilters are local to each invocation.
    let context: CIContext
    private let colorKernel: CIColorKernel?
    private let shoulderKernel: CIColorKernel?
    private let detailKernel: CIColorKernel?
    private let lumaKernel: CIColorKernel?
    private let offsetKernel: CIColorKernel?
    private let lightDetailKernel: CIColorKernel?
    private let lightEdgeKernel: CIColorKernel?
    private let grainKernel: CIColorKernel?
    private let subjectLiftKernel: CIColorKernel?
    // Not private: the water calm stages live in FilterEngine+WaterCalm.swift.
    let calmKernels: [String: CIColorKernel]
    /// False when the finishing kernel failed to load. Output then uses the weaker colour-matrix
    /// fallback, so owners with a DiagnosticRecorder report it.
    var finishingKernelAvailable: Bool { colorKernel != nil }
    /// The detail kernel, for the kernel-versus-mirror test (finishing on a solid image cannot exercise it).
    var detailKernelForTesting: CIColorKernel? { detailKernel }
    var lumaKernelForTesting: CIColorKernel? { lumaKernel }
    var offsetKernelForTesting: CIColorKernel? { offsetKernel }
    func calmKernelForTesting(_ name: String) -> CIColorKernel? { calmKernels[name] }
    static let workingSpace = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!
    static let photoSpace = CGColorSpace(name: CGColorSpace.displayP3)!
    /// `image` scaled down so its longer side is at most `maxPixel`, to a whole number of pixels on both sides.
    /// One ratio for both sides left a partial pixel row: a 6192 x 4128 photo at 1600 px is 1066.67 rows high. The
    /// stages that blur and clamp at the edge read that row, and the preview's top edge turned bright (m5 on the
    /// iPhone, 25 Oct 2026). The aspect changes by less than one pixel. Exports run at full size and never had it.
    static func downscaled(_ image: CIImage, maxPixel: CGFloat) -> CIImage {
        let extent = image.extent
        let ratio = min(1, maxPixel / max(extent.width, extent.height))
        guard ratio < 1, extent.width > 0, extent.height > 0 else { return image }
        let width = max(1, (extent.width * ratio).rounded()), height = max(1, (extent.height * ratio).rounded())
        return image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
            .concatenating(CGAffineTransform(scaleX: width / extent.width, y: height / extent.height)))
    }
    /// `memoryLimitMB` sets the most memory Core Image may use for one render. The default (256 MB) is
    /// too small for 4K video: it ran 3 times slower and used twice the memory (Mac, 22 Oct 2026,
    /// docs/PerformanceMeasurement.md). Nil keeps the system default.
    init(memoryLimitMB: Int? = nil) {
        var options: [CIContextOption: Any] = [.workingColorSpace: Self.workingSpace, .workingFormat: CIFormat.RGBAh, .cacheIntermediates: false]
        if let memoryLimitMB { options[.memoryTarget] = memoryLimitMB }
        if let device = MTLCreateSystemDefaultDevice() { context = CIContext(mtlDevice: device, options: options) }
        else { context = CIContext(options: options) }
        colorKernel = MetalKernels.color("UnderBlueFinishColor")
        shoulderKernel = MetalKernels.color("UnderBlueHighlightShoulder")
        detailKernel = MetalKernels.color("UnderBlueDetail")
        lumaKernel = MetalKernels.color("UnderBlueLumaTransfer")
        offsetKernel = MetalKernels.color("UnderBlueBlackOffset")
        lightDetailKernel = MetalKernels.color("UnderBlueLightDetail")
        lightEdgeKernel = MetalKernels.color("UnderBlueLightEdge")
        grainKernel = MetalKernels.color("UnderBlueGrain")
        subjectLiftKernel = MetalKernels.color("UnderBlueSubjectLift")
        var calm: [String: CIColorKernel] = [:]
        for name in ["UnderBlueCalmShare", "UnderBlueCalmSpread", "UnderBlueCalmWeight", "UnderBlueCalmPremultiply",
                     "UnderBlueWaterCalm", "UnderBlueCalmKeep", "UnderBlueVioletCalm", "UnderBlueWaterCore"] { calm[name] = MetalKernels.color(name) }
        calmKernels = calm
    }

    /// The subject lift. RestorationEngine.combined runs it once, on the blended output, before the
    /// violet calm. Inside the finishing kernel it would run on both paths and the blend would dilute it.
    func subjectLift(_ image: CIImage, lift: SubjectLift, waterShare: CIImage? = nil, signal: CIImage? = nil) -> CIImage {
        guard let subjectLiftKernel else { return image }
        let mask = lift.mask.image(matching: image.extent)
        // No share image means tier two is off: a fully water-like stand-in makes its term zero.
        let share = waterShare ?? CIImage(color: .white).cropped(to: image.extent)
        // No signal image means every pixel is all signal: tier two alone, sharpening at full weight.
        let signalImage = signal ?? CIImage(color: .white).cropped(to: image.extent)
        // The tier map, when the photo has one (E25). Without it the kernel splits tiers itself, as before.
        let tierImage = lift.tiers?.image(matching: image.extent) ?? CIImage(color: .black).cropped(to: image.extent)
        let short = min(image.extent.width, image.extent.height)
        func blur(_ input: CIImage, _ radius: Float) -> CIImage {
            let f = CIFilter.gaussianBlur()
            f.inputImage = input.clampedToExtent()
            f.radius = max(0.5, radius)
            return (f.outputImage ?? input).cropped(to: image.extent)
        }
        // A subject-only blur was tried here on 22 Oct 2026 and reverted. It cut the change just inside
        // the outline by about 20%, but the divide by a near-zero weight raised the change in the water
        // 0 to 4 px out from 0.0155 to 0.0207. The water side is the one that reads as a halo.
        let blurred = blur(image, Float(lift.detailRadius) * Float(short))
        let wide = blur(image, Float(lift.clarityRadius) * Float(short))
        let out = subjectLiftKernel.apply(extent: image.extent, arguments: [
            image, mask, blurred, wide, share, signalImage, tierImage,
            CIVector(x: CGFloat(lift.strength), y: CGFloat(lift.chromaCap),
                     z: CGFloat(lift.highlightStart), w: CGFloat(lift.noiseFloor)),
            CIVector(x: CGFloat(lift.chromaExponent), y: CGFloat(lift.contrast),
                     z: CGFloat(lift.contrastPivot), w: CGFloat(lift.tier2)),
            CIVector(x: CGFloat(lift.detail), y: CGFloat(lift.detailEdgeLow),
                     z: CGFloat(lift.detailEdgeHigh), w: CGFloat(lift.clarity)),
            CIVector(x: CGFloat(lift.highlights), y: CGFloat(lift.highlightKnee),
                     z: CGFloat(lift.maskLow), w: CGFloat(lift.maskHigh)),
            CIVector(x: CGFloat(lift.tier3), y: CGFloat(lift.highlights2),
                     z: CGFloat(lift.highlights3), w: lift.tiers == nil ? 0 : 1)])
        return (out ?? image).cropped(to: image.extent)
    }

    func apply(_ image: CIImage, settings: FilterSettings, edgeGuard: Bool = true, coresWater: Bool = true) -> CIImage {
        guard settings.preset != .original else { return image }
        return apply(image, correction: .make(analysis: settings.analysis, preset: settings.preset, adjustments: settings.adjustments),
                     intensity: settings.appliedIntensity, edgeGuard: edgeGuard, coresWater: coresWater)
    }
    /// `violetCalm` false leaves the violet calm to the caller: RestorationEngine.combined runs it once
    /// on the blended output.
    func apply(_ image: CIImage, correction: ColorCorrection, intensity: Float, calmWeight: CIImage? = nil,
               violetCalm calmsViolet: Bool = true, openWaterRed: Bool = false, edgeGuard: Bool = true, coresWater: Bool = true) -> CIImage {
        let amount = min(1, max(0, intensity.isFinite ? intensity : 0))
        guard amount > 0 else { return image }
        let calm = calmWeight ?? waterCalmWeight(image, correction: correction)
        let shown = blend(image, finishing(image, correction: correction, calmWeight: calm, openWaterRed: openWaterRed,
                                              edgeGuard: edgeGuard, coresWater: coresWater), amount: amount)
        return calmsViolet ? violetCalm(shown, source: image, calmWeight: calm) : shown
    }
    /// Applies a preset at full strength. Callers choose what the final intensity blends against.
    func finishing(_ image: CIImage, settings: FilterSettings) -> CIImage {
        guard settings.preset != .original else { return image }
        return finishing(image, correction: .make(analysis: settings.analysis, preset: settings.preset, adjustments: settings.adjustments))
    }
    /// Applies correction values at full strength. No values are derived here.
    /// `reference` is the source image the highlight shoulder takes its ceiling from; it defaults to
    /// `image`. The restored path passes the unrestored source, so restoration cannot raise the ceiling.
    /// `calmWeight` is waterCalmWeight of the source; it defaults to the weight of `image` itself.
    /// `openWaterRed` (video) keeps the red rebuild out of flat open water; see below.
    /// `edgeGuard` keeps the light detail away from strong edges (photos; video passes false). See below.
    /// `coresWater` takes the weak 3-12 px ripple off the water before colour (waterCore; photos, video passes false).
    /// Blur radius (share of the short side) of the open-water weight that mixes out the rebuilt red.
    static let openWaterBlur: Float = 0.03
    func finishing(_ image: CIImage, correction v: ColorCorrection, reference: CIImage? = nil, calmWeight: CIImage? = nil,
                   openWaterRed: Bool = false, edgeGuard: Bool = true, coresWater: Bool = true) -> CIImage {
        guard v != .identity else { return image }
        let side = Float(min(image.extent.width, image.extent.height))
        let short = side.isFinite && side > 0 ? side : 480
        let calm = calmWeight ?? waterCalmWeight(image, correction: v)
        let calmed = coresWater ? waterCore(waterCalm(image, weight: calm, short: short), weight: calm, short: short)
            : waterCalm(image, weight: calm, short: short)
        var corrected = colorStage(calmed, v)
        // Flat open water gets no rebuilt red. Video has one water colour per scene, but its sunlit
        // surface water is greener than that colour, so the hue gate took it for a subject and turned
        // it grey above a blue layer (instagram-media 2, 22 Oct 2026). A subject is not flat water, so
        // its weight is 0 and it keeps the rebuild. Photos and the CPU mirror are unchanged.
        if openWaterRed, v.redRebuild > 0, let calm, let keep = calmKernels["UnderBlueCalmKeep"] {
            var unrebuilt = v
            unrebuilt.redRebuild = 0
            // The weight is blurred wide. Raw, it drops to 0 right next to a small subject, and only that ring
            // got the rebuilt red: every fish in a whale shark clip wore a grey ring.
            let wide = CIFilter.gaussianBlur()
            wide.inputImage = calm.clampedToExtent()
            wide.radius = max(1, Self.openWaterBlur * short)
            let softCalm = (wide.outputImage ?? calm).cropped(to: image.extent)
            corrected = keep.apply(extent: image.extent, arguments: [colorStage(calmed, unrebuilt), corrected, softCalm]) ?? corrected
        }

        let controls = CIFilter.colorControls()
        controls.inputImage = corrected
        // The colour-matrix fallback does not implement reference adaptation or its tone step.
        let referenceStrength = colorKernel == nil ? 0 : v.referenceStrength
        let gain = 1 + (v.contrast - 1) * (1 - referenceStrength), brightness = v.brightness * (1 - referenceStrength)
        controls.saturation = v.saturation
        // Contrast and brightness go through UnderBlueBlackOffset, which gives the shadows a toe
        // instead of clipping them (FinishingMath.blackOffset). Without the kernel, CIColorControls does it.
        if offsetKernel == nil { controls.contrast = gain; controls.brightness = brightness }
        corrected = controls.outputImage ?? corrected
        if let offsetKernel {
            corrected = offsetKernel.apply(extent: image.extent, arguments: [
                corrected, CIVector(x: CGFloat(gain), y: CGFloat(brightness + (1 - gain) * 0.5), z: CGFloat(openWaterRed ? FinishingMath.videoShadowFloor : 0), w: 0)
            ]) ?? corrected
        }

        // The filter reads a neighbourhood. Fed the frame as it is, it changed the edge band on the
        // restored path on the Mac: the challenge clip got a vignette (corners up to 0.13 OKLab L brighter
        // than the ring around the centre, 1 Oct 2026). A clamped input keeps the edges. iOS had the same
        // symptom from another cause (the reference input in colorStage); see docs/Verification.md.
        let shadows = CIFilter.highlightShadowAdjust()
        shadows.inputImage = corrected.clampedToExtent()
        shadows.shadowAmount = v.shadowLift
        shadows.highlightAmount = v.highlightAmount
        corrected = (shadows.outputImage ?? corrected).cropped(to: image.extent)

        // A very large photo is cut here: the stages before and after each fit Core Image's intermediate limit, together not.
        corrected = materializedIfLarge(corrected)
        let unsharpened = corrected
        for (amount, radius) in [(v.clarity, v.clarityRadius), (v.definition, v.definitionRadius)] where amount > 0 {
            let mask = CIFilter.unsharpMask()
            mask.inputImage = corrected
            mask.radius = max(1, radius * short)
            mask.intensity = amount
            corrected = mask.outputImage ?? corrected
        }
        // Sharpen luminance only: on RGB the masks sharpen colour noise too. On the sunfish photo
        // (28 Sep 2026) this cut colour noise 27% in flat water and 34% on the fish; luminance was unchanged.
        if corrected !== unsharpened, let lumaKernel {
            corrected = lumaKernel.apply(extent: image.extent, arguments: [unsharpened, corrected]) ?? corrected
        }

        let sharpened = corrected
        // The local grain level (FinishingMath.grainRadius, grainSpread): the light detail fades on grainy texture
        // such as bright sand. Black (no fade) when the kernel is missing.
        let grain = grainMap(corrected, short: short) ?? CIImage(color: .black).cropped(to: image.extent)
        // Light rays inside bright light keep their contrast (FinishingMath.lightDetail). The kernel
        // gets the blur back from an unsharp mask (sharp = pixel + (pixel - blur)), as clarity does.
        // It runs here, before the fine detail. Placed last (after vibrance), with a blur or an unsharp
        // mask as its second input, it gave the Mac video path a vignette: the challenge clip's
        // frame edges up to 60 levels brighter, the centre unchanged (2 Oct 2026). The cause was
        // not found. The pixel values entering the kernel already had the bright edges.
        if let lightDetailKernel {
            let beforeLight = corrected
            let mask = CIFilter.unsharpMask()
            mask.inputImage = corrected
            mask.radius = max(2, FinishingMath.lightDetailRadius * short)
            mask.intensity = 1
            let sharp = (mask.outputImage ?? corrected).cropped(to: image.extent)
            corrected = lightDetailKernel.apply(extent: image.extent, arguments: [corrected, sharp, grain,
                CIVector(x: CGFloat(FinishingMath.lightDetailAmount), y: CGFloat(FinishingMath.lightDetailLow),
                         z: CGFloat(FinishingMath.lightDetailHigh), w: 0),
                CIVector(x: CGFloat(FinishingMath.lightDetailEdgeLow), y: CGFloat(FinishingMath.lightDetailEdgeHigh), z: CGFloat(FinishingMath.lightDetailGrainLow), w: CGFloat(FinishingMath.lightDetailGrainHigh))
            ]) ?? corrected
            // The kernel skips a strong edge itself, but not the water around it. Beside a bright fish the blur
            // takes in the fish, so the water reads darker than its broad light and the detail made it darker
            // still: a dark band 8 to 40 px wide (DSC03545, -0.02 OKLab L against the far water; the source
            // has none). So where the edge size, spread over half the radius, is large, the pixel keeps its
            // value from before the light detail. Light rays have small differences and keep it (E27, 24 Oct 2026).
            if edgeGuard, let lightEdgeKernel, let edge = lightEdgeKernel.apply(extent: image.extent, arguments: [beforeLight, sharp]) {
                let spread = CIFilter.gaussianBlur()
                spread.inputImage = edge.clampedToExtent()
                spread.radius = max(1, FinishingMath.lightDetailRadius * FinishingMath.lightEdgeSpread * short)
                let ramp = CIFilter.colorMatrix()
                ramp.inputImage = (spread.outputImage ?? edge).cropped(to: image.extent)
                let scale = 1 / CGFloat(FinishingMath.lightEdgeHigh - FinishingMath.lightEdgeLow)
                ramp.rVector = CIVector(x: scale, y: 0, z: 0, w: 0)
                ramp.biasVector = CIVector(x: -CGFloat(FinishingMath.lightEdgeLow) * scale, y: 0, z: 0, w: 0)
                let clamp = CIFilter.colorClamp()
                clamp.inputImage = ramp.outputImage
                // Water only (1 - calm.b, the source's own subject test): on IMG_7262 the guard also took the
                // detail off dark rock beside bright sand, and the rock went pale and soft.
                var guardMask = clamp.outputImage
                if let calm {
                    let water = CIFilter.colorMatrix()
                    water.inputImage = calm
                    water.rVector = CIVector(x: 0, y: 0, z: -1, w: 0)
                    water.biasVector = CIVector(x: 1, y: 0, z: 0, w: 0)
                    let both = CIFilter.multiplyCompositing()
                    both.inputImage = guardMask; both.backgroundImage = water.outputImage
                    let unit = CIFilter.colorClamp()
                    unit.inputImage = both.outputImage
                    guardMask = unit.outputImage
                }
                let mix = CIFilter.blendWithRedMask()
                mix.inputImage = beforeLight; mix.backgroundImage = corrected; mix.maskImage = guardMask
                corrected = (mix.outputImage ?? corrected).cropped(to: image.extent)
            }
        }
        // Fine detail: the pixel against its own small blur, on subjects only (UnderBlueDetail). The blur
        // reads a clamped image, so the border gets no dark rim. It also takes the source's own subject
        // test (calm.b): on the restored image the water beside a bright subject tested as subject, and
        // the layer drew a dark line there (IMG_7260 turtle, 1 px out: -3.6 L* against the far water; the
        // source +1.8; without the layer +1.1. 8 Oct 2026).
        if v.detail > 0, let detailKernel {
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = corrected.clampedToExtent()
            blur.radius = max(0.5, v.detailRadius * short)
            let blurred = (blur.outputImage ?? corrected).cropped(to: image.extent)
            corrected = detailKernel.apply(extent: image.extent, arguments: [
                corrected, blurred, image, calm ?? CIImage(color: .white).cropped(to: image.extent),
                CIVector(x: CGFloat(v.castGains.x), y: CGFloat(v.castGains.y), z: CGFloat(v.castGains.z), w: 0),
                CIVector(x: CGFloat(v.waterRedness), y: CGFloat(v.waterChroma), z: 0, w: 0),
                CIVector(x: CGFloat(v.waterLit.x), y: CGFloat(v.waterLit.y), z: CGFloat(v.waterLit.z), w: 0),
                CIVector(x: CGFloat(v.detail), y: CGFloat(v.detailFloor), z: CGFloat(FinishingMath.detailEdgeLow), w: CGFloat(FinishingMath.detailEdgeHigh)),
                CIVector(x: CGFloat(FinishingMath.detailShadowLow), y: CGFloat(FinishingMath.detailShadowHigh), z: 0, w: 0)
            ]) ?? corrected
        }

        // Open water drops the light detail and the fine detail: they sharpened its noise, most of it
        // beside a subject (FinishingMath.calmShare). The unsharp masks stay. Their dark fringe beside a
        // subject is broad and soft; with it gone from the open water only, its last few pixels became a
        // sharp dark line along the subject (IMG_7261 wrasse, 8 Oct 2026). Water noise is the same either
        // way, because the water is already calm before the colour stage.
        if let calm, let keep = calmKernels["UnderBlueCalmKeep"] {
            corrected = keep.apply(extent: image.extent, arguments: [sharpened, corrected, calm]) ?? corrected
        }

        if v.warmth != 0 {
            let warmth = CIFilter.temperatureAndTint()
            warmth.inputImage = corrected
            // The source is taken as lit at 6500 K + warmth and rendered at 6500 K, so a positive value warms.
            // (6500 to 6500 + warmth cooled the image: +300 K turned grey blue.) A green tint of 1 per 100 K
            // makes the shift yellow rather than orange, so pale blue water does not turn lavender. A cool
            // shift (Custom's Temperature down) gets no tint: the mirrored magenta tint moved grey to indigo.
            warmth.neutral = CIVector(x: CGFloat(6500 + v.warmth), y: CGFloat(-max(0, v.warmth) / 100))
            warmth.targetNeutral = CIVector(x: 6500, y: 0)
            corrected = warmth.outputImage ?? corrected
        }
        let vibrance = CIFilter.vibrance()
        vibrance.inputImage = corrected
        vibrance.amount = v.vibrance
        corrected = vibrance.outputImage ?? corrected
        // Every step above can push highlights past white, and none rolls them off, so the shoulder runs last.
        if let shoulderKernel {
            corrected = shoulderKernel.apply(extent: image.extent, arguments: [
                corrected, reference ?? image,
                CIVector(x: CGFloat(FinishingMath.shoulderWidth), y: CGFloat(FinishingMath.whiteLow),
                         z: CGFloat(FinishingMath.whiteHigh), w: CGFloat(FinishingMath.paleLow)),
                CIVector(x: CGFloat(FinishingMath.paleHigh), y: 0, z: 0, w: 0)
            ]) ?? corrected
        }
        return corrected.cropped(to: image.extent)
    }
    /// The local grain level (red, gamma luminance): each pixel against its small blur (FinishingMath.grainRadius px),
    /// spread over FinishingMath.grainSpread of the short side. Nil without the kernel.
    func grainMap(_ image: CIImage, short: Float) -> CIImage? {
        guard let grainKernel else { return nil }
        let small = CIFilter.gaussianBlur()
        small.inputImage = image.clampedToExtent()
        small.radius = FinishingMath.grainRadius
        guard let difference = grainKernel.apply(extent: image.extent, arguments: [image, (small.outputImage ?? image).cropped(to: image.extent)]) else { return nil }
        let wide = CIFilter.gaussianBlur()
        wide.inputImage = difference.clampedToExtent()
        wide.radius = max(1, FinishingMath.grainSpread * short)
        return wide.outputImage?.cropped(to: image.extent)
    }

    /// Pixel count above which a render is cut into pieces (materializedIfLarge). 20 and 24 MP stay one graph.
    static let materializeAbove = 30_000_000
    /// `image` rendered once into a half-float buffer in working values, when it is larger than `above`; the stages after
    /// it read the buffer. At 48 MP the whole chain of wide blurs needed about 400 MB of intermediates for one tile, above
    /// Core Image's 256 MB limit, and the export failed (iPhone 17, 26 Oct 2026). Cut once, before the sharpening, each
    /// part fits. Against the uncut render (Mac, 1 MP threshold): about 9% of pixels move by 1 level, at most 0.04% by 3
    /// or more. A 32-bit buffer was closer, but the app was killed for memory at 48 MP. One buffer of 8 bytes per pixel
    /// (390 MB at 48 MP) while the render runs. On a failure it returns `image`.
    func materializedIfLarge(_ image: CIImage, above: Int = FilterEngine.materializeAbove) -> CIImage {
        let e = image.extent
        guard e.width.isFinite, e.height.isFinite, Int(e.width) * Int(e.height) > above else { return image }
        let w = Int(e.width), h = Int(e.height)
        var data = Data(count: w * h * 8)
        let rendered: Bool = data.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return false }
            let destination = CIRenderDestination(bitmapData: base, width: w, height: h, bytesPerRow: w * 8, format: .RGBAh)
            destination.colorSpace = nil
            let origin = image.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
            do { _ = try context.startTask(toRender: origin, to: destination).waitUntilCompleted(); return true } catch { return false }
        }
        guard rendered else { return image }
        return CIImage(bitmapData: data, bytesPerRow: w * 8, size: CGSize(width: w, height: h), format: .RGBAh, colorSpace: nil)
            .transformed(by: CGAffineTransform(translationX: e.minX, y: e.minY))
    }
    private func colorStage(_ image: CIImage, _ v: ColorCorrection) -> CIImage {
        guard let colorKernel else {
            // Without the kernel keep the gains and a plain red rebuild; the tone curve is skipped.
            let matrix = CIFilter.colorMatrix()
            matrix.inputImage = image
            let g = v.castGains * v.neutralGains
            matrix.rVector = CIVector(x: CGFloat(g.x), y: CGFloat(v.redRebuild * g.y * 0.3), z: 0, w: 0)
            matrix.gVector = CIVector(x: 0, y: CGFloat(g.y), z: 0, w: 0)
            matrix.bVector = CIVector(x: 0, y: 0, z: CGFloat(g.z), w: 0)
            return matrix.outputImage ?? image
        }
        // The reference-adapted contribution reads the same image. A smoothed copy (CINoiseReduction, or a
        // small blur) of the restored image as a second kernel input made iOS render the frame wrong: its
        // edge rows broke and the whole output got about 7% darker, even at a reference strength of 0.0009
        // (simulator and iPhone 17, 1 Oct 2026). The Mac renders it differently, so the harness did not show
        // it. Without the smoothing the Mac harness measures more colour noise on m5 (sand 0.40 -> 0.76).
        let referenceInput = image
        return colorKernel.apply(extent: image.extent, arguments: [
            image, referenceInput, CIVector(x: CGFloat(v.castGains.x), y: CGFloat(v.castGains.y), z: CGFloat(v.castGains.z), w: 0),
            CIVector(x: CGFloat(v.waterTone.x), y: CGFloat(v.waterTone.y), z: CGFloat(v.waterTone.z), w: CGFloat(v.waterRedness)),
            CIVector(x: CGFloat(v.waterSaturation), y: CGFloat(v.waterChroma), z: CGFloat(v.redCeiling), w: CGFloat(v.violetGuard)),
            CIVector(x: CGFloat(v.redRebuild), y: CGFloat(v.redGateLow), z: CGFloat(v.redGateHigh), w: CGFloat(v.subjectRed)),
            CIVector(x: CGFloat(v.toneCurve), y: CGFloat(v.tonePivot), z: CGFloat(v.midLift), w: CGFloat(v.brightness + (1 - v.contrast) * 0.5)),
            CIVector(x: CGFloat(v.neutralGains.x), y: CGFloat(v.neutralGains.y), z: CGFloat(v.neutralGains.z), w: CGFloat(v.contrast)),
            CIVector(x: CGFloat(v.waterLit.x), y: CGFloat(v.waterLit.y), z: CGFloat(v.waterLit.z), w: CGFloat(v.lightGradient)),
            CIVector(x: CGFloat(v.subjectTone.x), y: CGFloat(v.subjectTone.y), z: CGFloat(v.subjectTone.z), w: 0),
            CIVector(x: CGFloat(v.referenceGains.x), y: CGFloat(v.referenceGains.y), z: CGFloat(v.referenceGains.z), w: CGFloat(v.referenceStrength))
        ]) ?? image
    }
    func blend(_ source: CIImage, _ target: CIImage, amount: Float) -> CIImage {
        // Dissolve interpolates complete results: 0 is exactly the source, 1 the target.
        let blend = CIFilter.dissolveTransition()
        blend.inputImage = source
        blend.targetImage = target
        blend.time = min(1, max(0, amount))
        return (blend.outputImage ?? source).cropped(to: source.extent)
    }
    func sdr(_ image: CIImage) -> CIImage {
        guard image.contentHeadroom > 1 else { return image }
        let tone = CIFilter.toneMapHeadroom()
        tone.inputImage = image
        tone.sourceHeadroom = image.contentHeadroom
        tone.targetHeadroom = 1
        return tone.outputImage ?? image
    }
}
