import CoreImage
import os
import simd
import CoreImage.CIFilterBuiltins

struct RestorationPixelResult: Sendable, Equatable {
    let color: SIMD3<Float>
    let hitTransmissionFloor: Bool
    let hitMaximumGain: Bool
}

enum RestorationMath {
    static func forward(clear: SIMD3<Float>, depth: Float, backscatterInfinity: SIMD3<Float>,
                        betaDirect: SIMD3<Float>, betaBackscatter: SIMD3<Float>) -> SIMD3<Float> {
        let z = safe(depth, fallback: 0, range: 0...1)
        var result = SIMD3<Float>(repeating: 0)
        for channel in 0..<3 {
            let directTransmission = exp(-max(0, safe(betaDirect[channel])) * z)
            let backscatterTransmission = exp(-max(0, safe(betaBackscatter[channel])) * z)
            result[channel] = max(0, safe(clear[channel])) * directTransmission
                + max(0, safe(backscatterInfinity[channel])) * (1 - backscatterTransmission)
        }
        return finite(result)
    }

    /// `broad` is the broad light around the pixel and `veilLevel` the plan's water level, for the
    /// local veil (localVeil). Without them the plan's veil is used as it is.
    static func inverse(observed: SIMD3<Float>, depth: Float, backscatterInfinity: SIMD3<Float>,
                        betaDirect: SIMD3<Float>, betaBackscatter: SIMD3<Float>,
                        limits: RestorationLimits, recoverability: SIMD3<Float> = .init(repeating: 1),
                        broad: SIMD3<Float>? = nil, veilLevel: Float = 0, middleHighlight: Bool = false) -> RestorationPixelResult {
        let source = finite(observed)
        let z = safe(depth, fallback: 0, range: 0...1)
        var corrected = SIMD3<Float>(repeating: 0)
        var hitFloor = false, hitGain = false
        var veil = SIMD3<Float>(repeating: 0)
        for channel in 0..<3 {
            veil[channel] = max(0, safe(backscatterInfinity[channel])) * (1 - exp(-max(0, safe(betaBackscatter[channel])) * z))
        }
        if let broad { veil = localVeil(veil, broad: finite(broad), level: veilLevel) }
        for channel in 0..<3 {
            let directTransmission = exp(-max(0, safe(betaDirect[channel])) * z)
            let transmission = max(safe(limits.transmissionFloor, fallback: 0.28, range: 0.01...1), directTransmission)
            let maximumGain = safe(limits.maximumGain[channel], fallback: 1, range: 1...16)
            let gain = min(1 / transmission, maximumGain)
            hitFloor = hitFloor || directTransmission <= limits.transmissionFloor
            hitGain = hitGain || gain >= maximumGain - 1e-5
            corrected[channel] = max(0, source[channel] - veil[channel]) * gain
        }
        // Video reads the middle channel, as in the kernel: blue water has one bright channel, a highlight has two.
        let sourcePeak = middleHighlight ? max(min(source.x, source.y), min(max(source.x, source.y), source.z))
                                         : max(source.x, source.y, source.z)
        let highlight = smoothstep(limits.highlightStart, limits.highlightEnd, sourcePeak) * 0.8
        corrected = corrected * (1 - highlight) + source * highlight
        let maximumOutput = safe(limits.maximumOutput, fallback: 1.15, range: 0.5...8)
        corrected = SIMD3(min(maximumOutput, max(0, corrected.x)),
                          min(maximumOutput, max(0, corrected.y)),
                          min(maximumOutput, max(0, corrected.z)))
        let recovery = SIMD3(min(1, max(0, recoverability.x)), min(1, max(0, recoverability.y)),
                             min(1, max(0, recoverability.z)))
        corrected = keepHueWhereDark(source: source, restored: source + (corrected - source) * recovery)
        corrected = keepBlueFamily(source: source, restored: corrected)
        corrected = keepWarmRatio(source: source, restored: corrected)
        return RestorationPixelResult(color: finite(corrected), hitTransmissionFloor: hitFloor, hitMaximumGain: hitGain)
    }

    /// Local veil. One veil per scene does not fit water whose light changes across the frame:
    /// toward the sun the real veil is brighter, and behind a fish school it is darker. With one veil,
    /// sunlit water kept a grey-pink band and the school turned into a hard shadow (challenge video,
    /// 32 to 38 s, 30 Sep 2026). So the veil scales with the broad light around the pixel (a blur of
    /// localVeilRadius of the short side), as a share of the scene's water level (RestorationPlan.veilLevel),
    /// within localVeilRange (localVeilScale).
    /// Its colour follows the broad light too, at the same luminance. In open water the water itself
    /// shows the veil's colour. The scene veil was bluer than whitish surface light, so taking it away
    /// left red and blue: video2's surface light turned pink or violet on 12.7% of the frame at 0 s
    /// (1.1% with the colour following). A level of zero means no local veil. The kernel mirrors it.
    static func localVeil(_ veil: SIMD3<Float>, broad: SIMD3<Float>, level: Float) -> SIMD3<Float> {
        guard level > 1e-4 else { return veil }
        let light = pointwiseMax(broad, .zero), broadLuminance = (light * ColorCorrection.luma).sum()
        let scaled = veil * localVeilScale(broadLuminance: broadLuminance, level: level)
        guard broadLuminance > 1e-4 else { return scaled }
        return light * ((scaled * ColorCorrection.luma).sum() / broadLuminance)
    }
    static func localVeilScale(broadLuminance: Float, level: Float) -> Float {
        guard level > 1e-4, broadLuminance.isFinite else { return 1 }
        return min(localVeilRange.upperBound, max(localVeilRange.lowerBound, max(0, broadLuminance) / level))
    }
    static let localVeilRadius: Float = 0.05
    static let localVeilRange: ClosedRange<Float> = 0.33...3

    /// Where veil removal leaves little light (far water is mostly veil), the channel that lost
    /// least (often red, which is recovered least) would dominate and turn the water red-brown or
    /// violet. There the source colour is kept, scaled to the restored level. The level is the
    /// plain channel sum, because blue, which carries water colour, barely counts in luminance.
    static func keepHueWhereDark(source: SIMD3<Float>, restored: SIMD3<Float>) -> SIMD3<Float> {
        let before = pointwiseMax(source, .zero).sum(), after = pointwiseMax(restored, .zero).sum()
        guard before > 1e-5 else { return restored }
        let kept = after / before
        let dark = 1 - smoothstep(darkLow, darkHigh, kept)
        return finite(restored + (pointwiseMax(source, .zero) * kept - restored) * dark)
    }
    static let darkLow: Float = 0.3, darkHigh: Float = 0.6

    /// A near, pale subject in blue water (a silver fish) read at far-water depth, as the video
    /// path's one constant depth does, loses nearly all its blue to the veil and turns lime.
    /// So a blue pixel (blue above red and green) that comes out green (green above blue) only
    /// because its green/blue ratio grew several times keeps its source hue, at the restored
    /// level (channel sum). Green, yellow and grey sources, and ordinary colour recovery
    /// (a smaller ratio change), are untouched. The Metal kernel mirrors it.
    static func keepBlueFamily(source: SIMD3<Float>, restored: SIMD3<Float>) -> SIMD3<Float> {
        let lit = pointwiseMax(source, .zero), now = pointwiseMax(restored, .zero)
        guard lit.sum() > 1e-5 else { return restored }
        let blue = smoothstep(blueLow, blueHigh, lit.z / max(max(lit.x, lit.y), 1e-4))
        let greenBlue = now.y / max(now.z, 1e-4)
        let green = smoothstep(greenLow, greenHigh, greenBlue)
        let growth = smoothstep(growthLow, growthHigh, greenBlue / max(lit.y / max(lit.z, 1e-4), 1e-4))
        let amount = blue * green * growth
        return finite(restored + (lit * (now.sum() / lit.sum()) - restored) * amount)
    }
    static let blueLow: Float = 1.0, blueHigh: Float = 1.1
    static let greenLow: Float = 1.1, greenHigh: Float = 1.4
    static let growthLow: Float = 4, growthHigh: Float = 8

    /// A pale source pixel whose red already reaches green lost no red to the water (surface
    /// light; see FinishingMath.uncast). The red-first transmission gain and the removal of a
    /// bluer veil still raised its red above green: the shark photo's surface went from 4.2% to
    /// 12.7% pink or violet on restoration alone (3.2% with this rule, 3 Oct 2026). So its
    /// restored red stays at or below green times the source red/green. The Metal kernel mirrors it.
    static func keepWarmRatio(source: SIMD3<Float>, restored: SIMD3<Float>) -> SIMD3<Float> {
        let lit = pointwiseMax(source, .zero)
        guard lit.sum() > 1e-5 else { return restored }
        let ceiling = max(restored.y, 0) * lit.x / max(lit.y, 1e-4)
        var kept = restored
        kept.x += (min(restored.x, ceiling) - restored.x) * FinishingMath.uncast(source)
        return finite(kept)
    }

    static func confidenceBlend(current: SIMD3<Float>, restored: SIMD3<Float>, confidence: Float) -> SIMD3<Float> {
        let amount = safe(confidence, fallback: 0, range: 0...1)
        return finite(current) * (1 - amount) + finite(restored) * amount
    }

    private static func smoothstep(_ low: Float, _ high: Float, _ value: Float) -> Float {
        let width = max(1e-5, high - low)
        let x = min(1, max(0, (value - low) / width))
        return x * x * (3 - 2 * x)
    }

    private static func safe(_ value: Float, fallback: Float = 0, range: ClosedRange<Float>? = nil) -> Float {
        guard value.isFinite else { return fallback }
        guard let range else { return value }
        return min(range.upperBound, max(range.lowerBound, value))
    }

    private static func finite(_ value: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(value.x.isFinite ? value.x : 0, value.y.isFinite ? value.y : 0, value.z.isFinite ? value.z : 0)
    }
}

final class RestorationEngine: Sendable {
    private let kernel: CIColorKernel?
    private let detailKernel: CIColorKernel?
    private let depthBlendKernel: CIColorKernel?
    private let subjectWeightKernel: CIColorKernel?
    private let subjectFreeLightKernel: CIColorKernel?
    private let liftKernel: CIColorKernel?
    private let signalKernel: CIColorKernel?
    private let objectColourKernel: CIColorKernel?
    private let objectColourVideoKernel: CIColorKernel?
    /// Video object colour values per scene and settings (videoObjectColourValues). Few entries: one per scene the
    /// preview or export is on, and the settings change only when a slider moves.
    let videoObjectCache = OSAllocatedUnfairLock(initialState: [VideoObjectCacheEntry]())
    /// Depth (normalized) from which a pixel takes the full restored result. See combined().
    static let nearDepth: Float = 0.25

    init() {
        kernel = MetalKernels.color("UnderBlueRestoration")
        detailKernel = MetalKernels.color("UnderBlueRestoredDetail")
        depthBlendKernel = MetalKernels.color("UnderBlueDepthBlend")
        subjectWeightKernel = MetalKernels.color("UnderBlueSubjectWeight")
        subjectFreeLightKernel = MetalKernels.color("UnderBlueSubjectFreeLight")
        liftKernel = MetalKernels.color("UnderBlueLiftToWide")
        signalKernel = MetalKernels.color("UnderBlueContrastTransmission")
        objectColourKernel = MetalKernels.color("UnderBlueObjectColour")
        objectColourVideoKernel = MetalKernels.color("UnderBlueObjectColourVideo")
    }

    /// The blur (share of the short side, at least 1.5 px) that splits the source into the part
    /// the restoration acts on and the fine detail. See restore(_:plan:).
    static let detailSplitRadius: Float = 0.0015
    /// The wide light that dark pixels are lifted to, in broad-light radii (video, see restore).
    static let liftWideScale: Float = 3

    /// The restoration removes the veil and divides by the transmission. On fine detail that is
    /// mostly noise: the veil takes signal, not noise, and the division then scales both. Far water
    /// got about twice the noise per signal (IMG_7260, 28 Sep 2026). So the restoration acts on a
    /// slightly blurred source, and the source's fine detail comes back at the pixel's own
    /// restoration ratio. The mean colour is the same; detail keeps its share of the signal.
    func restore(_ image: CIImage, plan: RestorationPlan, liftDark: Bool = false) throws -> CIImage {
        guard let kernel else { throw RestorationError.kernelUnavailable }
        let depth = try depthImage(plan.depth, matching: image.extent)
        let limits = plan.limits
        let short = Float(min(image.extent.width, image.extent.height))
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = image.clampedToExtent()
        blur.radius = max(1.5, Self.detailSplitRadius * (short.isFinite ? short : 0))
        let low = detailKernel == nil ? image : (blur.outputImage ?? image).cropped(to: image.extent)
        // The broad light around each pixel, for the local veil (RestorationMath.localVeil).
        let broadRadius = max(4, RestorationMath.localVeilRadius * (short.isFinite ? short : 0))
        func broadBlur(_ input: CIImage) -> CIImage {
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = input.clampedToExtent()
            blur.radius = broadRadius
            return (blur.outputImage ?? input).cropped(to: image.extent)
        }
        var broad = broadBlur(image)
        // Video has no photo mask. With liftDark, a pixel darker than the wide light around it (a dark
        // fish or shark) is lifted to that light before the broad blur, twice, so the dark pixels weigh
        // less in their own wide light. Water next to a dark subject then gets the veil of open water.
        // Without it that water kept more veil and showed a bright halo (instagram-media, 22 Oct 2026).
        if liftDark, plan.subjectMask == nil, let liftKernel {
            var lifted = low
            for _ in 0..<2 {
                let wideBlur = CIFilter.gaussianBlur()
                wideBlur.inputImage = lifted.clampedToExtent()
                wideBlur.radius = broadRadius * Self.liftWideScale
                let wide = (wideBlur.outputImage ?? lifted).cropped(to: image.extent)
                lifted = liftKernel.apply(extent: image.extent, arguments: [low, wide])?.cropped(to: image.extent) ?? lifted
            }
            broad = broadBlur(lifted)
        }
        // Outside the photo's subjects the broad light leaves them out: a blur of the source
        // weighted by (1 - mask), divided by the blur of the weight. See SubjectMask.
        if let subjects = plan.subjectMask, let subjectWeightKernel, let subjectFreeLightKernel {
            let mask = subjects.image(matching: image.extent)
            if let weighted = subjectWeightKernel.apply(extent: image.extent, arguments: [image, mask, 0]),
               let weight = subjectWeightKernel.apply(extent: image.extent, arguments: [image, mask, 1]),
               let free = subjectFreeLightKernel.apply(extent: image.extent, arguments: [
                   broadBlur(weighted), broadBlur(weight), broad, mask]) {
                broad = free.cropped(to: image.extent)
            }
        }
        let restoredLow = kernel.apply(extent: image.extent, arguments: [
            low, depth, broad,
            vector(plan.backscatterInfinity), vector(plan.betaDirect), vector(plan.betaBackscatter),
            CIVector(x: CGFloat(limits.transmissionFloor), y: CGFloat(limits.highlightStart),
                     z: CGFloat(limits.highlightEnd), w: CGFloat(limits.maximumOutput)),
            vector(limits.maximumGain), vector(plan.channelRecoverability),
            CIVector(x: CGFloat(plan.veilLevel), y: CGFloat(RestorationMath.localVeilRange.lowerBound),
                     z: CGFloat(RestorationMath.localVeilRange.upperBound), w: liftDark ? 1 : 0)
        ])
        guard let restoredLow else { throw RestorationError.kernelUnavailable }
        guard let detailKernel, low !== image else { return restoredLow.cropped(to: image.extent) }
        let output = detailKernel.apply(extent: image.extent, arguments: [image, low, restoredLow, vector(limits.maximumGain)])
        return (output ?? restoredLow).cropped(to: image.extent)
    }

    private func depthImage(_ map: NormalizedDepthMap, matching extent: CGRect) throws -> CIImage {
        let data = map.values.withUnsafeBytes { Data($0) }
        let depth = CIImage(bitmapData: data, bytesPerRow: map.width * MemoryLayout<Float>.size,
                            size: CGSize(width: map.width, height: map.height), format: .Rf, colorSpace: nil)
        // Clamped, then cropped: the scaled map is sampled between pixels, so at the border it read
        // the empty space outside the map. How much depended on the region the later filters asked
        // for, so a blur anywhere after the restoration changed the restored edge rows. The 2x2 test
        // plan's bottom rows lost 5% (VideoRestorationTests edge test 0.948 with the water calm, 8 Oct 2026).
        let scaled = depth.clampedToExtent().transformed(by: CGAffineTransform(scaleX: extent.width / CGFloat(map.width),
                                                                               y: extent.height / CGFloat(map.height)))
        return scaled.transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY)).cropped(to: extent)
    }

    private func vector(_ value: SIMD3<Float>) -> CIVector {
        CIVector(x: CGFloat(value.x), y: CGFloat(value.y), z: CGFloat(value.z), w: 0)
    }

    func combined(_ image: CIImage, plan: RestorationPlan, settings: FilterSettings,
                  filter: FilterEngine, subjectLift: SubjectLift? = nil) throws -> CIImage {
        try combined(image, plan: plan, values: corrections(settings: settings, plan: plan),
                     settings: settings, filter: filter, subjectLift: subjectLift)
    }

    /// combined() with correction values the caller already made. Video mixes two scenes' values here.
    func combined(_ image: CIImage, plan: RestorationPlan,
                  values: (current: ColorCorrection, restored: ColorCorrection),
                  settings: FilterSettings, filter: FilterEngine, video: Bool = false,
                  subjectLift: SubjectLift? = nil) throws -> CIImage {
        let amount = min(1, max(0, settings.appliedIntensity))
        guard settings.preset != .original else { return image }
        guard amount > 0 else {
            // Intensity 0 leaves the photo as it is. The subject strength is its own slider (Jake, 25 Oct 2026,
            // docs/ManualSubject.md), so the picked subjects still get their lift, on the untouched photo.
            guard let subjectLift else { return image }
            let share = subjectLift.tier2 > 0 || subjectLift.tier3 > 0 ? filter.waterShare(image, correction: values.current) : nil
            return lifted(image, subjectLift, filter, share, contrastTransmission(image, plan: plan))
        }
        // Both paths calm the water the source shows. On the restored image the water test read 0.65
        // in far water and below 0.2 near a subject, which left a noisy band (IMG_7260, 8 Oct 2026).
        let calm = filter.waterCalmWeight(image, correction: values.current)
        // Tier two of the lift reads the raw water share, not the spread calm weight.
        let share = (subjectLift?.tier2 ?? 0) > 0 || (subjectLift?.tier3 ?? 0) > 0
            ? filter.waterShare(image, correction: values.current) : nil
        // The tiers and the sharpening follow how much of an object's contrast survives the water.
        let liftSignal = subjectLift == nil ? nil : contrastTransmission(image, plan: plan)
        let current = filter.apply(image, correction: values.current, intensity: amount, calmWeight: calm, violetCalm: false, openWaterRed: video,
                                   edgeGuard: !video)
        let physicallyRestored = try restore(image, plan: plan, liftDark: video)
        let finished = filter.finishing(physicallyRestored, correction: values.restored, reference: image, calmWeight: calm, openWaterRed: video,
                                       edgeGuard: !video)
        let depthAware = filter.blend(image, finished, amount: amount)
        // Low-confidence fits approach the exact current UnderBlue output. So do the nearest pixels
        // (depth 0 to nearDepth): the restoration leaves them almost as they are, but the restored
        // values are made for the restored water. On the sunfish's belly (depth 0) the restored
        // water tone turned the unrestored cyan green (28 Sep 2026, O3: hue 150 -> 200).
        // A constant-depth plan (video, one depth per scene) keeps one weight for the frame.
        let weight = values.restored.physicalWeight
        let values = plan.depth.values
        guard let nearest = values.min(), let farthest = values.max(), farthest - nearest > 0.05,
              let depthBlendKernel else {
            return filter.violetCalm(lifted(filter.blend(current, depthAware, amount: weight), subjectLift, filter, share, liftSignal),
                                     source: image, calmWeight: calm)
        }
        let depth = try depthImage(plan.depth, matching: image.extent)
        let mixed = depthBlendKernel.apply(extent: image.extent, arguments: [current, depthAware, depth,
            CIVector(x: CGFloat(weight), y: CGFloat(Self.nearDepth), z: 0, w: 0)])
        let blended = (mixed ?? filter.blend(current, depthAware, amount: weight)).cropped(to: image.extent)
        let finishedFrame = filter.violetCalm(lifted(blended, subjectLift, filter, share, liftSignal), source: image, calmWeight: calm)
        // Photos only: video holds one depth per scene, so it never reaches this path, and the flag keeps it out too.
        guard !video else { return finishedFrame }
        return objectColour(finishedFrame, plan: plan, depth: depth, redLoss: settings.analysis.redLoss, context: filter.context)
    }

    /// The values of the object colour step (docs/RestorationExperiments.md, A2): made from the frame itself, at
    /// depth-map size, before the step. `gains` take the water's tint off objects; `redFromGreen` scales the red made
    /// from the green excess on near pixels; `strength` is the share of the tint taken (0 when objects carry none).
    struct ObjectColourValues: Equatable {
        var gains = SIMD3<Float>(repeating: 1)
        var redFromGreen: Float = 0
        var strength: Float = 0
        /// The water's own green excess (linear sRGB, after the gains): the red step starts above it.
        var waterExcess: Float = 0
    }

    /// `pixels` are linear Rec.2020 colours of the frame, one per depth value (row 0 on top), `depth` 0 near to 1 far.
    static func objectColourValues(pixels: [SIMD3<Float>], depth: [Float], redLoss: Float) -> ObjectColourValues {
        guard pixels.count == depth.count, !pixels.isEmpty else { return ObjectColourValues() }
        func mean(_ keep: (Float) -> Bool) -> SIMD3<Float>? {
            var sum = SIMD3<Float>(repeating: 0), n: Float = 0
            for (p, z) in zip(pixels, depth) where keep(z) && p.x.isFinite && p.y.isFinite && p.z.isFinite { sum += p; n += 1 }
            return n > 100 ? sum / n : nil
        }
        // Both ends need enough pixels to be measured; otherwise there is nothing to compare, so no step.
        guard let far = mean({ $0 > FinishingMath.objectFar }), let near = mean({ $0 < FinishingMath.objectNear }) else { return ObjectColourValues() }
        let w = ColorCorrection.oklab(far), n = ColorCorrection.oklab(near)
        let farChroma = (w.y * w.y + w.z * w.z).squareRoot()
        var strength: Float = 0
        if farChroma > 1e-6 {
            let lean = (n.y * w.y + n.z * w.z) / farChroma
            strength = min(1, max(0, lean / (0.5 * farChroma)))
        }
        // No objects near (the near pixels are water too): no tint step.
        let distance = simd_length(n - w)
        let t = min(1, max(0, (distance - FinishingMath.objectDistanceLow) / (FinishingMath.objectDistanceHigh - FinishingMath.objectDistanceLow)))
        strength *= t * t * (3 - 2 * t)
        // Near pixels as saturated as the water are water too; a far colour without a tint gives no direction.
        func smooth(_ x: Float, _ low: Float, _ high: Float) -> Float {
            let u = min(1, max(0, (x - low) / (high - low))); return u * u * (3 - 2 * u)
        }
        let nearSaturation = (n.y * n.y + n.z * n.z).squareRoot() / max(n.x, 1e-3), farSaturation = farChroma / max(w.x, 1e-3)
        strength *= 1 - smooth(nearSaturation / max(farSaturation, 1e-6), FinishingMath.objectSaturationRatioLow, FinishingMath.objectSaturationRatioHigh)
        strength *= smooth(farChroma, FinishingMath.objectFarChromaLow, FinishingMath.objectFarChromaHigh)
        if strength < FinishingMath.objectTintFloor { strength = 0 }
        let farSRGB = pointwiseMax(FinishingMath.rec2020ToSRGB * far, SIMD3(repeating: 1e-4))
        let luma = (farSRGB * ColorCorrection.luma).sum()
        let cap = FinishingMath.objectGainCap
        var gains = SIMD3<Float>(repeating: 1)
        if strength > 0 {
            for i in 0..<3 { gains[i] = min(cap, max(1 / cap, pow(luma / farSRGB[i], strength))) }
        }
        let water = FinishingMath.rec2020ToSRGB * far * gains
        return ObjectColourValues(gains: gains, redFromGreen: FinishingMath.objectRedK * max(0, redLoss), strength: strength,
                                  waterExcess: max(0, water.y - 0.5 * (water.x + water.z)))
    }

    /// Object colour step (UnderBlueObjectColour): reads the frame at depth-map size, makes the values, applies them.
    func objectColour(_ frame: CIImage, plan: RestorationPlan, depth: CIImage, redLoss: Float, context: CIContext) -> CIImage {
        guard let objectColourKernel else { return frame }
        let dw = plan.depth.width, dh = plan.depth.height
        guard dw > 0, dh > 0, frame.extent.width > 0, frame.extent.height > 0 else { return frame }
        let pixels = Self.workingPixels(frame, width: dw, height: dh, context: context)
        let values = Self.objectColourValues(pixels: pixels, depth: plan.depth.values, redLoss: redLoss)
        guard values.strength > 0 || values.redFromGreen > 0 else { return frame }
        func row(_ m: simd_float3x3, _ i: Int) -> CIVector { CIVector(x: CGFloat(m[0][i]), y: CGFloat(m[1][i]), z: CGFloat(m[2][i]), w: 0) }
        let to = FinishingMath.rec2020ToSRGB, from = FinishingMath.sRGBToRec2020
        let output = objectColourKernel.apply(extent: frame.extent, arguments: [frame, depth,
            row(to, 0), row(to, 1), row(to, 2), row(from, 0), row(from, 1), row(from, 2),
            CIVector(x: CGFloat(values.gains.x), y: CGFloat(values.gains.y), z: CGFloat(values.gains.z), w: CGFloat(values.redFromGreen)),
            CIVector(x: CGFloat(FinishingMath.objectNearFull), y: CGFloat(FinishingMath.objectNearNone), z: CGFloat(values.waterExcess), w: 0)])
        return (output ?? frame).cropped(to: frame.extent)
    }

    /// The frame scaled to `width` x `height`, as linear Rec.2020 pixels (row 0 on top, as the depth map).
    static func workingPixels(_ frame: CIImage, width: Int, height: Int, context: CIContext) -> [SIMD3<Float>] {
        let small = frame.transformed(by: CGAffineTransform(translationX: -frame.extent.minX, y: -frame.extent.minY)
            .concatenating(CGAffineTransform(scaleX: CGFloat(width) / frame.extent.width, y: CGFloat(height) / frame.extent.height)))
        var raw = [Float](repeating: 0, count: width * height * 4)
        context.render(small, toBitmap: &raw, rowBytes: width * 16, bounds: CGRect(x: 0, y: 0, width: width, height: height),
                       format: .RGBAf, colorSpace: FilterEngine.workingSpace)
        return (0..<(width * height)).map { SIMD3(raw[$0 * 4], raw[$0 * 4 + 1], raw[$0 * 4 + 2]) }
    }

    /// The values of the object colour step for video (docs/RestorationExperiments.md, A2 for video): step 2 only.
    /// `waterAB` is the water's OKLab a,b; pixels near that colour get no red, as a frame has no depth map.
    struct VideoObjectColourValues: Sendable, Equatable {
        var waterAB = SIMD2<Float>(0, 0)
        var waterExcess: Float = 0
        var redFromGreen: Float = 0

        /// Two scenes' values mixed, as the scene fade mixes the rest. A scene without values adds no red.
        static func mixed(_ a: Self?, _ b: Self?, amount: Float) -> Self? {
            guard let some = a ?? b else { return nil }
            let a = a ?? Self(waterAB: some.waterAB, waterExcess: some.waterExcess, redFromGreen: 0)
            let b = b ?? Self(waterAB: some.waterAB, waterExcess: some.waterExcess, redFromGreen: 0)
            let t = min(1, max(0, amount))
            return Self(waterAB: a.waterAB + (b.waterAB - a.waterAB) * t, waterExcess: a.waterExcess + (b.waterExcess - a.waterExcess) * t,
                        redFromGreen: a.redFromGreen + (b.redFromGreen - a.redFromGreen) * t)
        }
    }

    /// `pixels` are linear Rec.2020 colours of a keyframe after the video path, one per depth value. The water is the
    /// mean of the far pixels; nil when 100 or fewer.
    static func videoObjectColourValues(pixels: [SIMD3<Float>], depth: [Float], redLoss: Float) -> VideoObjectColourValues? {
        guard pixels.count == depth.count else { return nil }
        var sum = SIMD3<Float>(repeating: 0), n: Float = 0
        for (p, z) in zip(pixels, depth) where z > FinishingMath.objectFar && p.x.isFinite && p.y.isFinite && p.z.isFinite { sum += p; n += 1 }
        guard n > 100 else { return nil }
        let far = sum / n
        let lab = ColorCorrection.oklab(far)
        let water = FinishingMath.rec2020ToSRGB * far
        return VideoObjectColourValues(waterAB: SIMD2(lab.y, lab.z), waterExcess: max(0, water.y - 0.5 * (water.x + water.z)),
                                       redFromGreen: FinishingMath.objectRedK * max(0, redLoss))
    }

    /// Object colour step for video (UnderBlueObjectColourVideo).
    func videoObjectColour(_ frame: CIImage, values: VideoObjectColourValues) -> CIImage {
        guard let objectColourVideoKernel, values.redFromGreen > 0 else { return frame }
        func row(_ m: simd_float3x3, _ i: Int) -> CIVector { CIVector(x: CGFloat(m[0][i]), y: CGFloat(m[1][i]), z: CGFloat(m[2][i]), w: 0) }
        let to = FinishingMath.rec2020ToSRGB, from = FinishingMath.sRGBToRec2020
        let output = objectColourVideoKernel.apply(extent: frame.extent, arguments: [frame,
            row(to, 0), row(to, 1), row(to, 2), row(from, 0), row(from, 1), row(from, 2),
            CIVector(x: CGFloat(values.waterAB.x), y: CGFloat(values.waterAB.y),
                     z: CGFloat(FinishingMath.objectWaterDistanceLow), w: CGFloat(FinishingMath.objectWaterDistanceHigh)),
            CIVector(x: CGFloat(values.waterExcess), y: CGFloat(values.redFromGreen), z: 0, w: 0)])
        return (output ?? frame).cropped(to: frame.extent)
    }

    /// The subject lift, at the one place it may run. Both of combined()'s return points go through here,
    /// so a fix cannot land on only one of them (docs/SubjectEmphasis.md).
    private func lifted(_ image: CIImage, _ lift: SubjectLift?, _ filter: FilterEngine,
                        _ waterShare: CIImage?, _ signal: CIImage?) -> CIImage {
        guard let lift else { return image }
        return filter.subjectLift(image, lift: lift, waterShare: waterShare, signal: signal)
    }

    /// How much of an object's contrast survives the water in front of it (UnderBlueContrastTransmission),
    /// from the plan's own water fit, so clear water keeps a far reef sharp and murky water does not.
    /// A share of the pixel's light was tried first and dropped: the plan's veil sits below the bright
    /// water near the surface and above a dark diver, so it read water as object and the diver as veil
    /// (E17, 23 Oct 2026). Nil without the kernel or the depth.
    func contrastTransmission(_ image: CIImage, plan: RestorationPlan) -> CIImage? {
        guard let signalKernel, let depth = try? depthImage(plan.depth, matching: image.extent) else { return nil }
        return signalKernel.apply(extent: image.extent, arguments: [depth, vector(plan.betaDirect)])?.cropped(to: image.extent)
    }

    /// The correction values combined applies: one set for the source image, one for the restored image.
    func corrections(settings: FilterSettings, plan: RestorationPlan) -> (current: ColorCorrection, restored: ColorCorrection) {
        (ColorCorrection.make(analysis: settings.analysis, preset: settings.preset, adjustments: settings.adjustments),
         ColorCorrection.make(analysis: settings.analysis, preset: settings.preset, plan: plan, adjustments: settings.adjustments))
    }
}

/// One cached video object colour result (RestorationEngine.videoObjectColourValues).
struct VideoObjectCacheEntry: Sendable {
    struct Key: Sendable, Equatable {
        let start: Double
        let end: Double
        let settings: FilterSettings
        let preservesHDR: Bool
    }
    let key: Key
    let values: RestorationEngine.VideoObjectColourValues?
    static let capacity = 16
}
