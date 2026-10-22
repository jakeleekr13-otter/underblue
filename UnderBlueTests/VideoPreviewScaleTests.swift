import XCTest
import AVFoundation
@testable import UnderBlue

final class VideoPreviewScaleTests: XCTestCase {
    private let budget = VideoPreview.phonePixelRateBudget

    private func scale(_ width: CGFloat, _ height: CGFloat, fps: Int32, budget: Double?) -> Float {
        VideoPreview.renderScale(size: CGSize(width: width, height: height),
                                 frameDuration: CMTime(value: 1, timescale: fps), budget: budget)
    }

    func testNoBudgetKeepsFullSize() {
        XCTAssertEqual(scale(3840, 2160, fps: 60, budget: nil), 1)
    }

    func testLightClipsKeepFullSize() {
        XCTAssertEqual(scale(720, 1280, fps: 30, budget: budget), 1)
    }

    func testHeavyClipsScaleDownToTheBudget() {
        XCTAssertEqual(scale(1920, 1080, fps: 60, budget: budget), 0.49, accuracy: 0.01)
        XCTAssertEqual(scale(3840, 2160, fps: 60, budget: budget), 0.25, accuracy: 0.01)
    }

    func testInvalidFrameDurationKeepsFullSize() {
        let scale = VideoPreview.renderScale(size: CGSize(width: 1920, height: 1080), frameDuration: .zero, budget: budget)
        XCTAssertEqual(scale, 1)
    }
}
