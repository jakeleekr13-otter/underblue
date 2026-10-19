import XCTest
@testable import UnderBlue

final class PreviewZoomTests: XCTestCase {
    private let container = CGSize(width: 400, height: 300)

    func testFittedKeepsAspectInsideTheContainer() {
        XCTAssertEqual(PreviewZoom.fitted(CGSize(width: 4000, height: 2000), in: container), CGSize(width: 400, height: 200))
        XCTAssertEqual(PreviewZoom.fitted(CGSize(width: 1000, height: 1500), in: container), CGSize(width: 200, height: 300))
        XCTAssertEqual(PreviewZoom.fitted(.zero, in: container), .zero)
    }

    func testScaleStaysBetweenOneAndMaximum() {
        let content = PreviewZoom.fitted(CGSize(width: 4000, height: 3000), in: container)
        XCTAssertEqual(PreviewZoom(scale: 0.3).clamped(content: content, container: container).scale, 1)
        XCTAssertEqual(PreviewZoom(scale: 9).clamped(content: content, container: container).scale, PreviewZoom.maximum)
        XCTAssertEqual(PreviewZoom(scale: .nan).clamped(content: content, container: container).scale, 1)
        XCTAssertFalse(PreviewZoom(scale: 1).isZoomed)
        XCTAssertTrue(PreviewZoom(scale: 2).isZoomed)
    }

    func testResizeKeepsScaleAndCentrePointInsideTheNewFrame() {
        // Unfolding: the frame grows from 400x300 to 800x600, so the fitted image doubles and so does the offset.
        let zoomed = PreviewZoom(scale: 2, offset: CGSize(width: 100, height: -50))
        let grown = zoomed.resized(from: CGSize(width: 400, height: 300), to: CGSize(width: 800, height: 600),
                                   container: CGSize(width: 800, height: 600))
        XCTAssertEqual(grown, PreviewZoom(scale: 2, offset: CGSize(width: 200, height: -100)))
        // Folding into a narrow frame: the offset shrinks and is clamped, so no gap opens at the edge.
        let shrunk = PreviewZoom(scale: 2, offset: CGSize(width: 200, height: 150))
            .resized(from: CGSize(width: 400, height: 300), to: CGSize(width: 200, height: 150), container: CGSize(width: 200, height: 400))
        XCTAssertEqual(shrunk.scale, 2)
        XCTAssertEqual(shrunk.offset, CGSize(width: 100, height: 0))
        // An empty old size (first layout) leaves the zoom unchanged.
        XCTAssertEqual(zoomed.resized(from: .zero, to: CGSize(width: 400, height: 300), container: container), zoomed)
    }

    func testEditorUsesSidePanelInLandscapeAndOnWideNearSquareScreens() {
        XCTAssertTrue(EditorView.usesSidePanel(CGSize(width: 852, height: 393), regularWidth: false))
        XCTAssertFalse(EditorView.usesSidePanel(CGSize(width: 393, height: 760), regularWidth: false))
        // Near square: only a regular-width screen gets the side panel.
        XCTAssertTrue(EditorView.usesSidePanel(CGSize(width: 700, height: 760), regularWidth: true))
        XCTAssertFalse(EditorView.usesSidePanel(CGSize(width: 700, height: 760), regularWidth: false))
        // A tall regular-width screen keeps the bottom panel, so a wide photo is not squeezed beside it.
        XCTAssertFalse(EditorView.usesSidePanel(CGSize(width: 820, height: 1100), regularWidth: true))
    }

    func testPanStopsAtTheImageEdgesSoNoGapOpens() {
        // 400x300 content at 2x is 800x600, so it may move at most 200 horizontally and 150 vertically.
        let content = CGSize(width: 400, height: 300)
        let far = PreviewZoom(scale: 2, offset: CGSize(width: 900, height: -900)).clamped(content: content, container: container)
        XCTAssertEqual(far.offset, CGSize(width: 200, height: -150))
        // At 1x the image fits, so any offset snaps back to the centre.
        let fit = PreviewZoom(scale: 1, offset: CGSize(width: 50, height: 50)).clamped(content: content, container: container)
        XCTAssertEqual(fit.offset, .zero)
        // A letterboxed image (400x200 in 400x300) cannot move vertically until it is taller than the frame.
        let wide = PreviewZoom(scale: 1.2, offset: CGSize(width: 0, height: 80)).clamped(content: CGSize(width: 400, height: 200), container: container)
        XCTAssertEqual(wide.offset.height, 0)
    }
}
