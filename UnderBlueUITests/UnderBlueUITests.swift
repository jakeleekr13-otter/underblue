import XCTest

final class UnderBlueUITests: XCTestCase {
    @MainActor
    func testPhotoImportPresetsCompareExportSaveAndTrialGate() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-keychain=\(UUID().uuidString)", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Select Photo"].waitForExistence(timeout: 10))
        app.buttons["Select Photo"].tap()
        let cell = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        // A freshly booted simulator shows "Loading…" in the picker for longer than 8 s.
        guard cell.waitForExistence(timeout: 30) else {
            XCTFail("Photo picker contents: \(app.debugDescription)"); return
        }
        cell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Deep Dive"].waitForExistence(timeout: 15))
        app.buttons["Deep Dive"].tap()
        app.buttons["Compare"].tap()
        app.buttons["Compare"].tap()
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Photo editor"; screenshot.lifetime = .keepAlways
        add(screenshot)
        waitUntilEnabled(app.buttons["Export"])
        app.buttons["Export"].tap()
        XCTAssertTrue(app.staticTexts["Free trial"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Free export with an UnderBlue watermark."].exists)
        XCTAssertTrue(app.staticTexts["Free photos left: 3 of 3. Then 1 free photo every 24 hours."].exists)
        tapSheetExport(app)
        XCTAssertTrue(app.buttons["Save to Photos"].waitForExistence(timeout: 60))
        app.buttons["Save to Photos"].tap()
        XCTAssertTrue(app.staticTexts["Saved to Photos"].waitForExistence(timeout: 10))
        app.buttons["OK"].tap()
        // Three welcome photos: the second export is still free.
        app.buttons["Export"].tap()
        XCTAssertTrue(app.staticTexts["Free photos left: 2 of 3. Then 1 free photo every 24 hours."].waitForExistence(timeout: 8))
    }
    /// Closing the "Ready to save" sheet deletes the file. A swipe must not close it, Discard asks first,
    /// and a discarded free export gives the trial back (Jake, 4 Nov 2026).
    @MainActor
    func testReadySheetIgnoresSwipeAndDiscardKeepsTrial() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-keychain=\(UUID().uuidString)", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Select Photo"].waitForExistence(timeout: 10))
        app.buttons["Select Photo"].tap()
        let cell = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        // A freshly booted simulator shows "Loading…" in the picker for longer than 8 s.
        XCTAssertTrue(cell.waitForExistence(timeout: 30))
        cell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Deep Dive"].waitForExistence(timeout: 15))
        waitUntilEnabled(app.buttons["Export"])
        app.buttons["Export"].tap()
        let fullTrial = app.staticTexts["Free photos left: 3 of 3. Then 1 free photo every 24 hours."]
        XCTAssertTrue(fullTrial.waitForExistence(timeout: 5))
        tapSheetExport(app)
        let ready = app.staticTexts["Ready to save"]
        XCTAssertTrue(ready.waitForExistence(timeout: 60))
        // A plain swipeDown on the text does not close even a sheet that allows it. Drag the sheet's title bar to the bottom.
        let title = app.staticTexts["Export complete"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        title.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99)),
                    withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertTrue(app.buttons["Save to Photos"].waitForExistence(timeout: 3), "A swipe closed the sheet")
        app.buttons["Discard"].tap()
        let confirm = app.buttons["Discard export"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Your trial won’t be used."].exists)
        confirm.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: ready)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed)
        app.buttons["Export"].tap()
        XCTAssertTrue(fullTrial.waitForExistence(timeout: 8), "The discarded export used the trial")
    }
    /// Export stays disabled until the analysis ends. A tap before that does nothing.
    @MainActor
    private func waitUntilEnabled(_ element: XCUIElement) {
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 60), .completed, "Export stayed disabled")
    }
    /// Taps Export in the options sheet. Its identifier tells it apart from the editor's Export behind the sheet.
    @MainActor
    private func tapSheetExport(_ app: XCUIApplication) {
        let start = app.buttons["export-confirm"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
    }
    @MainActor
    func testVideoImportAndLandscapeEditor() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-keychain=\(UUID().uuidString)", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Select Video"].waitForExistence(timeout: 10))
        app.buttons["Select Video"].tap()
        let cell = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 8))
        cell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Compare"].waitForExistence(timeout: 15))
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        app.buttons["Compare"].tap()
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Landscape video editor"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["Export"].tap()
        XCTAssertTrue(app.staticTexts["video-trial-description"].waitForExistence(timeout: 8))
    }
    @MainActor
    func testHomeAndPaywall() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Select Video"].waitForExistence(timeout: 10))
        app.buttons["Get Pro"].tap()
        XCTAssertTrue(app.staticTexts["One-time purchase. Every dive."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Restore Purchase"].exists)
        XCTAssertFalse(app.buttons["Subscribe"].exists)
    }
}
