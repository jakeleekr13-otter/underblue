import CoreGraphics
import CoreImage

/// Tiers two and three of the subject lift (docs/SubjectEmphasis.md), as one soft map that both the lift
/// and the picker outline use. The outline is the same map cut at 0.5. Before 24 Oct 2026 the outline left
/// out sand, glow and bubbles while the lift still brightened them; one map keeps the two in step.
///
/// Each test below is a soft ramp, not a cut, so the lift makes no step at an edge.
/// - Not water: 1 - water share (FilterEngine.waterShare, alpha) at least 0.5, outside the Vision groups.
/// - In front: nearer than the open water by `depthMargin`. Light in the water (the sunlit surface, bubbles)
///   fails the colour test for water but sits at the water's depth. An object sits in front of it.
///   Measured 24 Oct 2026: open water 0.91 to 1.0, surface glow 0.88 to 0.90, bubbles 0.95 to 0.97,
///   white fish 0.73 to 0.79 (DSC03696, DSC03545).
/// - Textured: sand is a flat surface under even light, so it holds little local contrast. A reef, a wreck or a
///   fish has relief and shadow. Mean gradient of gamma luminance (`texture`), measured 24 Oct 2026:
///   m5 sand 0.009 and 0.027; front white fish 0.045; reef, coral and wreck 0.052 to 0.10. Jake: sand is no tier.
/// - No Vision group term. The lift multiplies the map by (1 - the picked mask), so a picked subject gets
///   tier one only. A subject the user excluded is treated like the scene around it, by its own water,
///   depth and texture: no emphasis, and no hole in the reef (Jake, 24 Oct 2026: an excluded subject must
///   still look natural). The drawing removes the picked groups the same way (`drawing(excluding:)`).
/// - Tier two weight = object x t, tier three weight = object x (1 - t), t the contrast transmission.
///   They are equal at t = 0.5 in every photo. The outline draws tier two where t is at least 0.5.
/// - Pieces and holes too small to draw are cleaned on the outline. The map is multiplied by the cleaned
///   region, feathered, so the lift leaves out what the outline leaves out.
///
/// They are shown, not picked: a layer has no instances to tap.
struct SubjectTiers: Sendable {
    let width: Int
    let height: Int
    /// The cleaned regions, before the picks: 1 inside, 0 outside. Row 0 is the top row, as in SubjectMask.
    let tier2: [Float]
    let tier3: [Float]
    /// The soft weights the lift reads (SubjectLift.tiers).
    let map: SubjectTierMap

    static let transmissionSplit: Float = 0.5
    /// A piece below this share of the frame is noise: it is removed, and a hole this small is filled.
    /// 0.2% removed the front white fish on DSC03545 (0.093% of the frame, JPG and RAW). Jake wants it kept;
    /// the fish behind it (0.03%) may go (24 Oct 2026). The depth test already keeps specks in the water out.
    static let minimumPieceShare: Float = 0.0005
    /// A hole inside a region below this share is filled. The texture test left many small smooth patches
    /// inside the DSC03696 reef, each drawn as its own ring.
    static let minimumHoleShare: Float = 0.01
    /// Open water: a water share at least this high. Its median depth is the depth of the water.
    static let openWaterShare: Float = 0.9
    /// How much nearer than the open water a pixel must be: the centre of `depthRamp`.
    /// The surface glow on DSC03696 sat 0.05 to 0.07 nearer.
    static let depthMargin: Float = 0.1
    /// With less open water than this share of the frame, the water's depth is not known and the depth test is off.
    static let minimumOpenWaterShare: Float = 0.01
    /// Below this texture a surface is flat, like sand: the centre of `textureRamp`.
    /// Between m5's sand (0.027) and the front white fish (0.045).
    static let minimumTexture: Float = 0.035
    /// The soft ramps around each cut. First values, agreed with the subject-lift session on 24 Oct 2026.
    static let notWaterRamp: ClosedRange<Float> = 0.4...0.6
    static let textureRamp: ClosedRange<Float> = 0.025...0.045
    /// In front: full weight at (water depth - 0.15), none at (water depth - 0.05).
    static let depthRamp: ClosedRange<Float> = 0.05...0.15
    /// The feather on the cleaned region, in grid pixels each way (a 5 x 5 box).
    static let featherRadius = 2

    static func smoothstep(_ range: ClosedRange<Float>, _ x: Float) -> Float {
        let t = min(1, max(0, (x - range.lowerBound) / (range.upperBound - range.lowerBound)))
        return t * t * (3 - 2 * t)
    }

    var isEmpty: Bool { !tier2.contains(1) && !tier3.contains(1) }

    /// The map and the cleaned regions from per-pixel values of the same size. They do not depend on the picks.
    /// `depth` is the plan's normalised depth, 0 nearest; nil turns the depth test off.
    /// `texture` is from `texture(luma:width:height:)`; nil turns the texture test off.
    static func make(waterShare: [Float], transmission: [Float], depth: [Float]? = nil,
                     texture: [Float]? = nil, width: Int, height: Int) -> SubjectTiers? {
        let count = width * height
        guard width > 1, height > 1, waterShare.count == count, transmission.count == count,
              depth.map({ $0.count == count }) ?? true, texture.map({ $0.count == count }) ?? true else { return nil }
        let water = depth.flatMap { waterDepth(waterShare: waterShare, depth: $0) }
        var object = [Float](repeating: 0, count: count)
        for i in 0..<count {
            var w = smoothstep(notWaterRamp, 1 - min(1, max(0, waterShare[i])))
            if let water, let depth { w *= 1 - smoothstep(water - depthRamp.upperBound...water - depthRamp.lowerBound, depth[i]) }
            if let texture { w *= smoothstep(textureRamp, texture[i]) }
            object[i] = w
        }
        // The outline: the same map at 0.5, split by t, cleaned for drawing.
        var two = [Bool](repeating: false, count: count), three = two
        for i in 0..<count where object[i] >= 0.5 {
            if transmission[i] >= transmissionSplit { two[i] = true } else { three[i] = true }
        }
        let minimum = max(1, Int(Float(count) * minimumPieceShare)), hole = max(1, Int(Float(count) * minimumHoleShare))
        let cleanTwo = cleaned(two, width: width, height: height, minimum: minimum, hole: hole)
        let cleanThree = cleaned(three, width: width, height: height, minimum: minimum, hole: hole)
        let a = cleanTwo.map { $0 ? Float(1) : 0 }, b = cleanThree.map { $0 ? Float(1) : 0 }
        // The lift: the soft weights inside the cleaned region, feathered. A filled hole takes the
        // weight around it, so the lift has no ring where the outline has none.
        let kept = boxMean(zip(a, b).map { max($0, $1) }, width: width, height: height, radius: featherRadius)
        let neighbour = boxMean(object, width: width, height: height, radius: featherRadius * 4)
        var map2 = [Float](repeating: 0, count: count), map3 = map2
        for i in 0..<count {
            let inside = max(a[i], b[i]) > 0
            let weight = (inside && object[i] < 0.5 ? max(object[i], neighbour[i]) : object[i]) * kept[i]
            let t = min(1, max(0, transmission[i]))
            map2[i] = weight * t
            map3[i] = weight * (1 - t)
        }
        return SubjectTiers(width: width, height: height, tier2: a, tier3: b,
                            map: SubjectTierMap(width: width, height: height, tier2: map2, tier3: map3))
    }

    /// The tier lines for the picker, with the picked groups taken out, as the lift takes them out.
    struct Drawing: Sendable {
        let tier2Outline: CGImage?
        let tier3Outline: CGImage?
    }

    /// `picked` is the picked mask on any grid (nearest sample). Nil means nothing is picked.
    func drawing(excluding picked: SubjectMask?) -> Drawing {
        var a = tier2, b = tier3
        if let picked, picked.width > 0, picked.height > 0, picked.values.count == picked.width * picked.height {
            for y in 0..<height {
                let py = min(picked.height - 1, y * picked.height / height)
                for x in 0..<width {
                    let px = min(picked.width - 1, x * picked.width / width)
                    if picked.values[py * picked.width + px] >= 0.5 { a[y * width + x] = 0; b[y * width + x] = 0 }
                }
            }
        }
        return Drawing(tier2Outline: SubjectCandidates.outline(a, width: width, height: height, radius: 2),
                       tier3Outline: SubjectCandidates.outline(b, width: width, height: height, radius: 2))
    }

    /// The mean over a (2 x radius + 1) square around each pixel, through a summed-area table.
    static func boxMean(_ values: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        guard values.count == width * height, radius > 0 else { return values }
        var table = [Double](repeating: 0, count: (width + 1) * (height + 1))
        for y in 0..<height {
            var line = 0.0
            for x in 0..<width {
                line += Double(values[y * width + x])
                table[(y + 1) * (width + 1) + x + 1] = table[y * (width + 1) + x + 1] + line
            }
        }
        var output = [Float](repeating: 0, count: width * height)
        for y in 0..<height { for x in 0..<width {
            let x0 = max(0, x - radius), x1 = min(width, x + radius + 1), y0 = max(0, y - radius), y1 = min(height, y + radius + 1)
            let sum = table[y1 * (width + 1) + x1] - table[y0 * (width + 1) + x1] - table[y1 * (width + 1) + x0] + table[y0 * (width + 1) + x0]
            output[y * width + x] = Float(sum / Double((x1 - x0) * (y1 - y0)))
        } }
        return output
    }

    /// Local contrast per pixel: the mean, over a window of 1% of the short side, of the gradient of `luma`
    /// (gamma luminance). The gradient spans 1/400 of the short side each way, so the value does not
    /// depend on the grid size. It is the average of the horizontal and vertical central differences.
    static func texture(luma: [Float], width: Int, height: Int) -> [Float] {
        guard width > 2, height > 2, luma.count == width * height else { return [] }
        let short = Float(min(width, height))
        let step = max(1, Int((short / 400).rounded())), radius = max(1, Int((short * 0.01).rounded()))
        func at(_ x: Int, _ y: Int) -> Float { luma[min(height - 1, max(0, y)) * width + min(width - 1, max(0, x))] }
        var gradient = [Float](repeating: 0, count: width * height)
        for y in 0..<height { for x in 0..<width {
            gradient[y * width + x] = (abs(at(x + step, y) - at(x - step, y)) + abs(at(x, y + step) - at(x, y - step))) / 2
        } }
        return boxMean(gradient, width: width, height: height, radius: radius)
    }

    /// The median depth of the open water, or nil when the frame holds too little of it.
    static func waterDepth(waterShare: [Float], depth: [Float]) -> Float? {
        let water = zip(waterShare, depth).filter { $0.0 >= openWaterShare && $0.1.isFinite }.map(\.1).sorted()
        guard !water.isEmpty, Float(water.count) >= Float(depth.count) * minimumOpenWaterShare else { return nil }
        return water[water.count / 2]
    }

    /// Removes pieces smaller than `minimum` pixels, then fills holes smaller than `hole` (default: `minimum`). 4-connected.
    static func cleaned(_ region: [Bool], width: Int, height: Int, minimum: Int, hole: Int? = nil) -> [Bool] {
        let kept = dropSmall(region, value: true, width: width, height: height, minimum: minimum)
        return dropSmall(kept, value: false, width: width, height: height, minimum: hole ?? minimum)
    }

    /// Flips every 4-connected piece of `value` smaller than `minimum` pixels.
    private static func dropSmall(_ input: [Bool], value: Bool, width: Int, height: Int, minimum: Int) -> [Bool] {
        var output = input
        var seen = [Bool](repeating: false, count: input.count)
        var stack: [Int] = [], piece: [Int] = []
        for start in input.indices where input[start] == value && !seen[start] {
            stack = [start]; piece = []; seen[start] = true
            while let i = stack.popLast() {
                piece.append(i)
                let x = i % width, y = i / width
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                where nx >= 0 && ny >= 0 && nx < width && ny < height {
                    let n = ny * width + nx
                    if !seen[n] && input[n] == value { seen[n] = true; stack.append(n) }
                }
            }
            if piece.count < minimum { for i in piece { output[i] = !value } }
        }
        return output
    }

    /// One channel of `image` over its extent, `width` by `height`, row 0 on top. No colour management.
    static func channel(_ image: CIImage, _ index: Int, width: Int, height: Int, context: CIContext) -> [Float] {
        var pixels = [Float](repeating: 0, count: width * height * 4)
        let extent = image.extent
        let fitted = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
            .concatenating(CGAffineTransform(scaleX: CGFloat(width) / extent.width, y: CGFloat(height) / extent.height)))
        context.render(fitted, toBitmap: &pixels, rowBytes: width * 16,
                       bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBAf, colorSpace: nil)
        // The bitmap's first row is the top of the bounds (testChannelReadPutsTheTopRowFirst).
        return (0..<(width * height)).map { pixels[$0 * 4 + index] }
    }
}
