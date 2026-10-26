import XCTest
@testable import UnderBlue

final class VideoColourTrackTests: XCTestCase {
    private let times = (0..<90).map { Double($0) / 30 }

    private func ratio(_ c: SIMD3<Float>) -> Float { c.x / c.y }

    /// The napoleon wrasse clip's pulse (26 Oct 2026): red 2.8x for 10 frames, green and blue nearly steady.
    func testShortRedPulseIsTakenOut() throws {
        let water = SIMD3<Float>(0.028, 0.063, 0.475)
        let means = times.indices.map { $0 >= 40 && $0 < 50 ? SIMD3<Float>(0.076, 0.069, 0.600) : water }
        let track = try XCTUnwrap(VideoColourTrack.make(times: times, means: means))
        let corrected = means[45] * track.gain(at: times[45])
        XCTAssertEqual(ratio(corrected), ratio(water), accuracy: 0.1 * ratio(water))
        // Brightness is kept.
        let y = { (c: SIMD3<Float>) in (c * VideoColourTrack.luminance).sum() }
        XCTAssertEqual(y(corrected), y(means[45]), accuracy: 1e-4)
        // Steady frames are left as they are.
        for g in [track.gain(at: times[5]), track.gain(at: times[80])] {
            XCTAssertEqual(g.x, 1, accuracy: 1e-4); XCTAssertEqual(g.y, 1, accuracy: 1e-4); XCTAssertEqual(g.z, 1, accuracy: 1e-4)
        }
    }

    /// A change that lasts, such as a new scene, keeps its colour once the window has passed it.
    func testLastingChangeIsKept() throws {
        let means = times.indices.map { $0 < 45 ? SIMD3<Float>(0.03, 0.06, 0.48) : SIMD3<Float>(0.09, 0.12, 0.30) }
        let track = try XCTUnwrap(VideoColourTrack.make(times: times, means: means))
        for index in [5, 30, 60, 85] {
            let g = track.gain(at: times[index])
            XCTAssertEqual(g.x, 1, accuracy: 1e-4); XCTAssertEqual(g.z, 1, accuracy: 1e-4)
        }
    }

    /// Blue water with no red: noise in the red mean must not become a large red gain.
    func testNoiseInAChannelNearZeroStaysSmall() throws {
        let means = times.indices.map { SIMD3<Float>(0.0005 * Float($0 % 3), 0.33, 0.71) }
        let track = try XCTUnwrap(VideoColourTrack.make(times: times, means: means))
        for index in times.indices {
            let g = track.gain(at: times[index])
            // Without the floor this is 0 or infinite.
            XCTAssertEqual(g.x, 1, accuracy: 0.05)
        }
    }

    func testBlackFramesAndShortClips() {
        XCTAssertNil(VideoColourTrack.make(times: [0, 1], means: [.zero, .zero]))
        let track = VideoColourTrack.make(times: [0, 0.1, 0.2], means: [.zero, .zero, .zero])
        XCTAssertEqual(track?.gain(at: 0.1), SIMD3(repeating: 1))
    }
}
