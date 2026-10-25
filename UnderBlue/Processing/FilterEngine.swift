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
    private let calmKernels: [String: CIColorKernel]
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
                     "UnderBlueWaterCalm", "UnderBlueCalmKeep", "UnderBlueVioletCalm"] { calm[name] = MetalKernels.color(name) }
        calmKernels = calm
    }

    /// The subject lift. RestorationEngine.combined runs it once, on the blended output, before the
    /// violet calm. Inside the finishing kernel it would run on both paths and the blend would dilute it.
    /// The per-pixel water share, before the calm chain spreads it. Tier two of the lift reads its
    /// complement: a reef or a wreck is not open water, and Vision rarely returns one.
    func waterShare(_ basis: CIImage, correction v: ColorCorrection) -> CIImage? {
        guard let shareKernel = calmKernels["UnderBlueCalmShare"] else { return nil }
        let short = Float(min(basis.extent.width, basis.extent.height))
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = basis.clampedToExtent()
        blur.radius = max(0.5, FinishingMath.calmBlurRadius * (short.isFinite && short > 0 ? short : 480))
        let smooth = (blur.outputImage ?? basis).cropped(to: basis.extent)
        return shareKernel.apply(extent: basis.extent, arguments: [smooth,
            CIVector(x: CGFloat(v.castGains.x), y: CGFloat(v.castGains.y), z: CGFloat(v.castGains.z), w: 0),
            CIVector(x: CGFloat(v.waterRedness), y: CGFloat(v.waterChroma), z: 0, w: 0),
            CIVector(x: CGFloat(v.waterLit.x), y: CGFloat(v.waterLit.y), z: CGFloat(v.waterLit.z), w: CGFloat(v.lightGradient))])
    }

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

    func apply(_ image: CIImage, settings: FilterSettings, edgeGuard: Bool = true) -> CIImage {
        guard settings.preset != .original else { return image }
        return apply(image, correction: .make(analysis: settings.analysis, preset: settings.preset, adjustments: settings.adjustments),
                     intensity: settings.appliedIntensity, edgeGuard: edgeGuard)
    }
    /// `violetCalm` false leaves the violet calm to the caller: RestorationEngine.combined runs it once
    /// on the blended output.
    func apply(_ image: CIImage, correction: ColorCorrection, intensity: Float, calmWeight: CIImage? = nil,
               violetCalm calmsViolet: Bool = true, openWaterRed: Bool = false, edgeGuard: Bool = true) -> CIImage {
        let amount = min(1, max(0, intensity.isFinite ? intensity : 0))
        guard amount > 0 else { return image }
        let calm = calmWeight ?? waterCalmWeight(image, correction: correction)
        let shown = blend(image, finishing(image, correction: correction, calmWeight: calm, openWaterRed: openWaterRed,
                                              edgeGuard: edgeGuard), amount: amount)
        return calmsViolet ? violetCalm(shown, source: image, calmWeight: calm) : shown
    }
    /// Violet the correction made loses its chroma; a pixel that was violet in the source keeps it
    /// (FinishingMath.violetCalm). It runs once, on the colour that is shown. Per path it was wrong on
    /// m5: the restored path left the sand lavender and the source path cyan, and their blend was
    /// neutral (chroma 0.017); calming the restored lavender alone left the blend cyan (0.020).
    /// It only lowers chroma at the same lightness, so no channel crosses white.
    /// `calmWeight` (waterCalmWeight of the source) tells water from subjects; nil treats all as subject.
    func violetCalm(_ image: CIImage, source: CIImage, calmWeight: CIImage?) -> CIImage {
        guard let kernel = calmKernels["UnderBlueVioletCalm"] else { return image }
        let water = calmWeight ?? CIImage(color: .black).cropped(to: image.extent)
        return (kernel.apply(extent: image.extent, arguments: [image, source, water,
            CIVector(x: CGFloat(FinishingMath.violetCalmAmount), y: CGFloat(FinishingMath.violetWaterHue), z: 0, w: 0)]) ?? image).cropped(to: image.extent)
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
    /// Blur radius (share of the short side) of the open-water weight that mixes out the rebuilt red.
    static let openWaterBlur: Float = 0.03
    func finishing(_ image: CIImage, correction v: ColorCorrection, reference: CIImage? = nil, calmWeight: CIImage? = nil,
                   openWaterRed: Bool = false, edgeGuard: Bool = true) -> CIImage {
        guard v != .identity else { return image }
        let side = Float(min(image.extent.width, image.extent.height))
        let short = side.isFinite && side > 0 ? side : 480
        let calm = calmWeight ?? waterCalmWeight(image, correction: v)
        let calmed = waterCalm(image, weight: calm, short: short)
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
    /// The water calm weight (r) and water share (g) of `basis`, read with its values `v`. Nil when a
    /// kernel failed to load; the finishing then runs without the calm. See FinishingMath.calmShare.
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

    func waterCalmWeight(_ basis: CIImage, correction v: ColorCorrection) -> CIImage? {
        guard v != .identity, let shareKernel = calmKernels["UnderBlueCalmShare"],
              let spreadKernel = calmKernels["UnderBlueCalmSpread"], let weightKernel = calmKernels["UnderBlueCalmWeight"] else { return nil }
        let extent = basis.extent
        let side = Float(min(extent.width, extent.height))
        let short = side.isFinite && side > 0 ? side : 480
        func blurred(_ image: CIImage, _ radius: Float) -> CIImage {
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = image.clampedToExtent()
            blur.radius = max(0.5, radius * short)
            return (blur.outputImage ?? image).cropped(to: extent)
        }
        let smooth = blurred(basis, FinishingMath.calmBlurRadius)
        let gains = CIVector(x: CGFloat(v.castGains.x), y: CGFloat(v.castGains.y), z: CGFloat(v.castGains.z), w: 0)
        let water = CIVector(x: CGFloat(v.waterRedness), y: CGFloat(v.waterChroma), z: 0, w: 0)
        let waterLit = CIVector(x: CGFloat(v.waterLit.x), y: CGFloat(v.waterLit.y), z: CGFloat(v.waterLit.z), w: CGFloat(v.lightGradient))
        guard let share = shareKernel.apply(extent: extent, arguments: [smooth, gains, water, waterLit]),
              let spread = spreadKernel.apply(extent: extent, arguments: [smooth, blurred(share, FinishingMath.calmWindowRadius), share])
        else { return nil }
        return weightKernel.apply(extent: extent, arguments: [share, blurred(spread, FinishingMath.calmWindowRadius), basis, gains, water, waterLit,
            CIVector(x: CGFloat(FinishingMath.calmFlatLow), y: CGFloat(FinishingMath.calmFlatHigh), z: 0, w: 0)])
    }
    /// Open water moves toward a blur of water pixels only, before the colour stage. See waterCalmWeight.
    private func waterCalm(_ image: CIImage, weight: CIImage?, short: Float) -> CIImage {
        guard let weight, let premultiply = calmKernels["UnderBlueCalmPremultiply"], let calm = calmKernels["UnderBlueWaterCalm"],
              let water = premultiply.apply(extent: image.extent, arguments: [image, weight]) else { return image }
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = water.clampedToExtent()
        blur.radius = max(0.5, FinishingMath.calmBlurRadius * short)
        let waterBlur = (blur.outputImage ?? water).cropped(to: image.extent)
        return calm.apply(extent: image.extent, arguments: [image, waterBlur, weight]) ?? image
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
    /// How far the white reference's hue must sit from the water's hue, in degrees, before it is
    /// trusted. Below the low bound it is a water-lit surface and counts for nothing.
    static let neutralHueLow: Float = 25, neutralHueHigh: Float = 35

    /// `subjects` is the photo's subject mask. A white reference on a subject is trusted whatever its
    /// hue (see the hue gate below). Video has no mask, so it keeps the hue gate alone.
    func analyze(_ image: CIImage, subjects: SubjectMask? = nil) -> WaterAnalysis {
        let source = sdr(image)
        let extent = source.extent
        guard !extent.isEmpty, extent.width.isFinite, extent.height.isFinite else { return .neutral }
        let size = 48
        // Lanczos, not a plain affine transform. A 48 px sample of a 5472 px photo is a 114x
        // reduction, and the default sampler reads a handful of source pixels per output pixel. What
        // it reads is up to the implementation, so a Mac and a phone read different samples from one
        // file. Lanczos takes every pixel in. It brought the water colour into agreement; the white
        // reference's share still differs, which is why the hue gate below exists (docs/JpegInput.md, J5).
        func sample(_ input: CIImage, colorSpace: CGColorSpace?) -> [Float] {
            let moved = input.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            let resample = CIFilter.lanczosScaleTransform()
            resample.inputImage = moved
            resample.scale = Float(CGFloat(size) / extent.height)
            resample.aspectRatio = Float(extent.height / extent.width)
            let scaled = (resample.outputImage ?? moved
                .transformed(by: CGAffineTransform(scaleX: CGFloat(size) / extent.width, y: CGFloat(size) / extent.height)))
                .cropped(to: CGRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size)))
            var pixels = [Float](repeating: 0, count: size * size * 4)
            context.render(scaled, toBitmap: &pixels, rowBytes: size * 4 * MemoryLayout<Float>.size,
                           bounds: CGRect(x: 0, y: 0, width: size, height: size), format: .RGBAf, colorSpace: colorSpace)
            return pixels
        }
        let pixels = sample(source, colorSpace: Self.workingSpace)
        // The mask goes through the same resample, so each value sits on its own pixel. No colour
        // matching: the mask is a weight, not a colour.
        let onSubject = subjects.map { sample($0.image(matching: extent), colorSpace: nil) }
        var red: Float = 0, green: Float = 0, blue: Float = 0, luminance: [Float] = [], saturation: Float = 0
        // s is the candidate's subject weight, 0 when there is no mask.
        var colors: [(c: SIMD3<Float>, s: Float)] = []
        var lit: Float = 0, high: Float = 0, litLuminance: [Float] = []
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = pixels[i], g = pixels[i+1], b = pixels[i+2]
            let l = r * 0.2126 + g * 0.7152 + b * 0.0722
            // Bright share counts clipped pixels too: a blown white belly is a bright area.
            if l.isFinite, l > 0.015 { lit += 1; litLuminance.append(l); if l >= 0.35 { high += 1 } }
            guard l.isFinite, l > 0.015, l < 0.85 else { continue }
            red += max(0, r); green += max(0, g); blue += max(0, b); luminance.append(l)
            colors.append((SIMD3(max(0, r), max(0, g), max(0, b)), onSubject.map { min(1, max(0, $0[i])) } ?? 0))
            let top = max(r, g, b)
            saturation += top > 0 ? (top - min(r, g, b)) / top : 0
        }
        guard !luminance.isEmpty else { return .neutral }
        luminance.sort()
        let n = Float(luminance.count)
        let surviving = max(0.001, (green + blue) / 2)
        let loss = max(0, min(1, 1 - red / surviving))
        // Open water is the least red part of an underwater scene; subjects are redder.
        colors.sort { $0.c.x / max(1e-4, $0.c.y + $0.c.z) < $1.c.x / max(1e-4, $1.c.y + $1.c.z) }
        let waterCount = max(1, colors.count / 3)
        let water = colors.prefix(waterCount).reduce(SIMD3<Float>(repeating: 0)) { $0 + $1.c } / Float(waterCount)
        // White reference candidates: outside the least red third (so not open water), among the
        // brightest fifth, clearly brighter than the water and no more colourful than it. The ceiling
        // carried 10% of slack until 23 Oct 2026. A camera JPEG's water is more saturated, so that
        // slack let blue-lit coral in, and the white reference then greyed it by adding red
        // (docs/JpegInput.md, J3).
        let waterChroma = ColorCorrection.oklch(water).y, waterLuminance = (water * ColorCorrection.luma).sum()
        let brightCut = max(luminance[min(luminance.count - 1, luminance.count * 8 / 10)], waterLuminance * 1.25)
        // A candidate more colourful than the water still counts when its hue is far from the water's.
        // Sand lit green under blue water is that case: r14's sand held chroma 0.133, above its water's,
        // so it was no reference and stayed mint in every version (docs/SubjectEmphasis.md, E20).
        // Blue-lit coral, the reason the slack went in J3, sits at the water's hue and stays out.
        let waterHue = ColorCorrection.oklch(water).z
        func farFromWater(_ c: SIMD3<Float>) -> Bool {
            let gap = abs(ColorCorrection.oklch(c).z - waterHue).truncatingRemainder(dividingBy: 360)
            return min(gap, 360 - gap) >= Self.neutralHueHigh
        }
        // Each candidate is split by its subject weight s: s of it is on a subject, 1 - s is scene.
        var scene = SIMD3<Float>(repeating: 0), sceneCount: Float = 0
        var subject = SIMD3<Float>(repeating: 0), subjectCount: Float = 0
        for (c, s) in colors.dropFirst(waterCount) where (c * ColorCorrection.luma).sum() >= brightCut
            && (ColorCorrection.oklch(c).y <= min(0.2, waterChroma) || (ColorCorrection.oklch(c).y <= 0.2 && farFromWater(c))) {
            scene += c * (1 - s); sceneCount += 1 - s
            subject += c * s; subjectCount += s
        }
        // A reference whose hue is the water's own hue is not a white surface. It is coral or rock
        // lit by the water, and greying it takes the water's colour out of the whole frame: the reef
        // then reads red (docs/JpegInput.md, J5). Trust grows with the angle between the two hues.
        // The bounds sit in an empty band: across eval/real, eval/market, eval/aquacolorfix and the
        // five camera pairs, the gap is either 24.8 degrees or less, or 36.7 or more.
        // A white belly lit by the water sits low too (the manta in AquaColorFix pair 4, 23.5 degrees).
        // Hue cannot tell it from coral, but the subject mask can: a reference on a detected subject
        // is an animal or a diver, not the reef, so it skips the gate (docs/SubjectEmphasis.md, E16).
        let sceneMean = sceneCount > 0 ? scene / sceneCount : SIMD3<Float>(repeating: 0)
        let hueGap = abs(ColorCorrection.oklch(sceneMean).z - ColorCorrection.oklch(water).z)
            .truncatingRemainder(dividingBy: 360)
        let angle = min(hueGap, 360 - hueGap)
        let t = min(1, max(0, (angle - Self.neutralHueLow) / (Self.neutralHueHigh - Self.neutralHueLow)))
        let sceneTrust = sceneCount > 0 ? t * t * (3 - 2 * t) : 0
        let trusted = sceneTrust * sceneCount + subjectCount
        let neutralCount = sceneCount + subjectCount
        // Without a trusted subject reference the colour is the scene mean, as before the mask.
        let neutral = subjectCount > 0 && trusted > 0 ? (scene * sceneTrust + subject) / trusted : sceneMean
        let trust = neutralCount > 0 ? trusted / neutralCount : 0
        return WaterAnalysis(redLoss: loss, cyanDominance: max(0, min(1, (surviving - red) / surviving)),
            exposure: min(0.12, max(0, (0.22 - luminance[luminance.count/2]) * 0.6)),
            contrast: luminance[luminance.count * 9 / 10] - luminance[luminance.count / 10], saturation: saturation / n,
            meanRed: red / n, meanGreen: green / n, meanBlue: blue / n, midLuminance: luminance[luminance.count / 2],
            waterRed: water.x, waterGreen: water.y, waterBlue: water.z,
            neutralRed: neutral.x, neutralGreen: neutral.y, neutralBlue: neutral.z,
            neutralShare: neutralCount / n * trust,
            highShare: lit > 0 ? high / lit : 0,
            lightShare: lit > 0 ? Float(litLuminance.filter { $0 >= waterLuminance * WaterAnalysis.lightShareRatio }.count) / lit : 0)
    }
}
