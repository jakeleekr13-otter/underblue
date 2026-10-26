import XCTest
import CoreImage
@testable import UnderBlue

/// PhotoOrbs (D3, docs/RestorationExperiments.md): a soft orb on water comes off at its own place; a bubble cluster stays.
final class PhotoOrbsTests: XCTestCase {
    private let engine = FilterEngine()
    private let width = 400, height = 300
    private let water = SIMD3<Float>(0.05, 0.15, 0.30)

    /// Linear working-space water with a little fixed noise. `add` adds light at (x, y), row 0 on top.
    private func image(_ add: (Int, Int) -> Float) -> (CIImage, [Float]) {
        var seed: UInt32 = 12345
        var values = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height { for x in 0..<width {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let noise = (Float(seed >> 8) / Float(1 << 24) - 0.5) * 0.004
            for c in 0..<3 { values[(y * width + x) * 4 + c] = water[c] + noise + add(x, y) }
        }}
        let data = values.withUnsafeBytes { Data($0) }
        return (CIImage(bitmapData: data, bytesPerRow: width * 16, size: CGSize(width: width, height: height),
                        format: .RGBAf, colorSpace: FilterEngine.workingSpace), values)
    }

    private func pixels(_ image: CIImage) -> [Float] {
        var out = [Float](repeating: 0, count: width * height * 4)
        engine.context.render(image, toBitmap: &out, rowBytes: width * 16, bounds: CGRect(x: 0, y: 0, width: width, height: height),
                              format: .RGBAf, colorSpace: FilterEngine.workingSpace)
        return out
    }

    private func orb(_ x: Int, _ y: Int, _ cx: Int, _ cy: Int) -> Float {
        let d2 = Float((x - cx) * (x - cx) + (y - cy) * (y - cy))
        return 0.03 * exp(-d2 / (2 * 5 * 5))
    }

    func testSoftOrbOnWaterIsTakenOffAtItsOwnPlace() throws {
        // Off centre in y, so a flipped factor image would miss it and mark (120, 210) instead.
        let (source, before) = image { self.orb($0, $1, 120, 90) }
        let found = try XCTUnwrap(PhotoOrbs.detect(source, share: nil, subjects: nil, depth: nil, context: engine.context))
        XCTAssertTrue(found.patches.contains { (120 - $0.x) >= 0 && (120 - $0.x) < $0.width && (90 - $0.y) >= 0 && (90 - $0.y) < $0.height })
        let after = pixels(found.applied(to: source))
        let centre = (90 * width + 120) * 4 + 1, mirror = (210 * width + 120) * 4 + 1, far = (250 * width + 330) * 4 + 1
        // The orb adds 0.03 at its centre; most of it comes off.
        XCTAssertLessThan(after[centre] - water.y, 0.01)
        XCTAssertGreaterThan(before[centre] - water.y, 0.025)
        XCTAssertEqual(after[mirror], before[mirror], accuracy: 0.0005)
        XCTAssertEqual(after[far], before[far], accuracy: 0.0005)
    }

    func testBubbleClusterStays() {
        // Twelve small sharp bright dots within 40 px: bubbles, not orbs.
        let dots = (0..<12).map { (200 + ($0 % 4) * 11 - 16, 150 + ($0 / 4) * 13 - 13) }
        let (source, _) = image { x, y in
            dots.reduce(0) { sum, d in
                let d2 = Float((x - d.0) * (x - d.0) + (y - d.1) * (y - d.1))
                return sum + 0.2 * exp(-d2 / 2)
            }
        }
        let found = PhotoOrbs.detect(source, share: nil, subjects: nil, depth: nil, context: engine.context)
        let touched = found?.patches.contains { $0.x < 230 && $0.x + $0.width > 170 && $0.y < 180 && $0.y + $0.height > 120 } ?? false
        XCTAssertFalse(touched)
    }

    func testBrightSpotStays() {
        // Four times the orb: brighter than PhotoOrbs.defaultMaxBump, like a small pale fish.
        let (source, _) = image { 4 * self.orb($0, $1, 120, 90) }
        let found = PhotoOrbs.detect(source, share: nil, subjects: nil, depth: nil, context: engine.context)
        XCTAssertFalse(found?.spots.contains { abs($0.x - 120) < 10 && abs($0.y - 90) < 10 } ?? false)
        // Without the cap it is found, so the cap is what keeps it.
        let uncapped = PhotoOrbs.detect(source, share: nil, subjects: nil, depth: nil, context: engine.context, maxBump: nil)
        XCTAssertTrue(uncapped?.spots.contains { abs($0.x - 120) < 10 && abs($0.y - 90) < 10 } ?? false)
    }

    func testNoOrbOutsideTheWater() {
        // The water share is the alpha channel of FilterEngine.waterShare; zero means no water anywhere.
        let (source, _) = image { self.orb($0, $1, 120, 90) }
        let share = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 0)).cropped(to: source.extent)
        XCTAssertNil(PhotoOrbs.detect(source, share: share, subjects: nil, depth: nil, context: engine.context))
    }
}
