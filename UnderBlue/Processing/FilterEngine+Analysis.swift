import CoreImage
import CoreImage.CIFilterBuiltins

/// The water analysis of a photo or a video keyframe (WaterAnalysis).
extension FilterEngine {
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
