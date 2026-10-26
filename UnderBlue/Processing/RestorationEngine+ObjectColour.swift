import CoreImage
import simd

/// The object colour step (docs/RestorationExperiments.md, A2): photos (objectColour) and video (videoObjectColour).
extension RestorationEngine {
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

    /// Object colour step (UnderBlueObjectColour): reads `measuredOn` (default: the frame) at depth-map size, makes the
    /// values, applies them to the frame.
    /// `depthTrust` (RestorationEngine.depthTrust): below half, depth does not show where the water is (open water), so
    /// step 2 takes the video rule: red by colour distance from the water, not by depth. Sunlit water near the sun read
    /// near (depth 0.69-0.77) on the hammerhead clip stills and turned pink with the depth rule (26 Oct 2026).
    func objectColour(_ frame: CIImage, measuredOn measured: CIImage? = nil, plan: RestorationPlan, depth: CIImage,
                      redLoss: Float, context: CIContext, depthTrust: Float = 1) -> CIImage {
        guard let objectColourKernel else { return frame }
        let dw = plan.depth.width, dh = plan.depth.height
        guard dw > 0, dh > 0, frame.extent.width > 0, frame.extent.height > 0 else { return frame }
        let pixels = Self.workingPixels(measured ?? frame, width: dw, height: dh, context: context)
        var values = Self.objectColourValues(pixels: pixels, depth: plan.depth.values, redLoss: redLoss)
        var colourRule: VideoObjectColourValues?
        if depthTrust < 0.5, values.redFromGreen > 0 {
            // Step 2 by colour, on the measured frame after step 1's gains.
            let gains = values.gains
            let stepped = pixels.map { FinishingMath.sRGBToRec2020 * (FinishingMath.rec2020ToSRGB * $0 * gains) }
            colourRule = Self.videoObjectColourValues(pixels: stepped, depth: plan.depth.values, redLoss: redLoss)
            values.redFromGreen = 0
        }
        guard values.strength > 0 || values.redFromGreen > 0 else {
            return colourRule.map { videoObjectColour(frame, values: $0) } ?? frame
        }
        func row(_ m: simd_float3x3, _ i: Int) -> CIVector { CIVector(x: CGFloat(m[0][i]), y: CGFloat(m[1][i]), z: CGFloat(m[2][i]), w: 0) }
        let to = FinishingMath.rec2020ToSRGB, from = FinishingMath.sRGBToRec2020
        let output = objectColourKernel.apply(extent: frame.extent, arguments: [frame, depth,
            row(to, 0), row(to, 1), row(to, 2), row(from, 0), row(from, 1), row(from, 2),
            CIVector(x: CGFloat(values.gains.x), y: CGFloat(values.gains.y), z: CGFloat(values.gains.z), w: CGFloat(values.redFromGreen)),
            CIVector(x: CGFloat(FinishingMath.objectNearFull), y: CGFloat(FinishingMath.objectNearNone), z: CGFloat(values.waterExcess), w: 0)])
        let stepOne = (output ?? frame).cropped(to: frame.extent)
        return colourRule.map { videoObjectColour(stepOne, values: $0) } ?? stepOne
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
