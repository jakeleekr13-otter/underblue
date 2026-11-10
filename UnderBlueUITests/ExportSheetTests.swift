import XCTest

final class ExportSheetTests: XCTestCase {
    @MainActor
    func testVideoExportSheetShowsActionAndEstimates() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-keychain=export-sheet",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["Select Video"].waitForExistence(timeout: 10))
        app.buttons["Select Video"].tap()
        let video = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        // The picker can show "Loading…" for more than 8 s (the photo tests wait 30 s too).
        guard video.waitForExistence(timeout: 30) else {
            XCTFail("Video picker contents: \(app.debugDescription)")
            return
        }
        video.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let export = app.buttons["Export"]
        XCTAssertTrue(export.waitForExistence(timeout: 30))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: export)
        waitForExpectations(timeout: 60)
        attach(app.screenshot(), named: "editor-controls")
        export.tap()

        let confirm = app.buttons["export-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        XCTAssertTrue(confirm.isHittable, "Export action must be visible without scrolling")
        attach(app.screenshot(), named: "export-sheet-estimating")

        let estimate = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '~'")).firstMatch
        XCTAssertTrue(estimate.waitForExistence(timeout: 120), "No export-time estimate appeared")
        sleep(5)
        attach(app.screenshot(), named: "export-sheet-estimates")

        // A free export is 1080p at Standard quality only (Jake, 10 Nov 2026).
        let quality = app.segmentedControls["export-quality"]
        XCTAssertTrue(quality.waitForExistence(timeout: 5), "No quality control: \(app.debugDescription)")
        // The pinned Export button covers the bottom of the sheet. A tap there starts an export, so scroll the
        // control above it first (a tap on "High" behind the button started an export, 10 Nov 2026).
        for _ in 0..<3 where quality.frame.maxY > confirm.frame.minY - 8 { app.swipeUp() }
        XCTAssertLessThan(quality.frame.maxY, confirm.frame.minY, "The quality control is still behind the Export button")
        XCTAssertTrue(quality.buttons["Standard"].isSelected, "A free export uses Standard")
        attach(app.screenshot(), named: "export-sheet-quality")
        // A tap on a Pro-only choice must not change the selection.
        quality.buttons["High"].tap()
        XCTAssertTrue(quality.buttons["Standard"].isSelected, "High must not be selectable for a free user")
        app.swipeDown()
        let quick = app.staticTexts["Quick"]
        if quick.waitForExistence(timeout: 3) { quick.tap() }
        let summary = app.staticTexts["1920 × 1080 · SDR · HEVC"]
        XCTAssertTrue(summary.waitForExistence(timeout: 3), "Quick must not be selectable for a free user: \(app.debugDescription)")
        attach(app.screenshot(), named: "export-sheet-free-taps")
        // This SDR fixture cannot export HDR, so a tap on HDR must leave SDR selected.
        let range = app.segmentedControls["video-range"]
        // The form builds rows only on screen, so scroll until the control exists and clears the Export button.
        for _ in 0..<4 where !range.exists || range.frame.maxY > confirm.frame.minY - 8 { app.swipeUp() }
        XCTAssertLessThan(range.frame.maxY, confirm.frame.minY, "The color control is still behind the Export button")
        range.buttons["HDR"].tap()
        XCTAssertTrue(range.buttons["SDR"].isSelected, "HDR must not be selectable for an SDR video")
    }

    private func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
