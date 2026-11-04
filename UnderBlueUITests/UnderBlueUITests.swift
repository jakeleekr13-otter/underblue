import XCTest

extension XCUIApplication {
    /// "Select Photos" when the free trial or Pro allows several photos, else "Select Photo" (4 Nov 2026).
    var selectPhotoButton: XCUIElement { buttons.matching(NSPredicate(format: "label BEGINSWITH 'Select Photo'")).firstMatch }
    /// A picker for several photos needs Add (or Done). A picker for one closes on the tap.
    func confirmPhotoPicker() {
        for label in ["Add", "Done"] where buttons[label].waitForExistence(timeout: 2) { buttons[label].tap(); return }
    }
}

final class UnderBlueUITests: XCTestCase {
    @MainActor
    func testPhotoImportPresetsCompareExportSaveAndTrialGate() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-keychain=\(UUID().uuidString)", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.selectPhotoButton.waitForExistence(timeout: 10))
        app.selectPhotoButton.tap()
        let cell = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        // A freshly booted simulator shows "Loading…" in the picker for longer than 8 s.
        guard cell.waitForExistence(timeout: 30) else {
            XCTFail("Photo picker contents: \(app.debugDescription)"); return
        }
        cell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.confirmPhotoPicker()
        XCTAssertTrue(app.buttons["Deep Dive"].waitForExistence(timeout: 15))
        // The presets wait for the analysis, as Export does. Read the preset first: once it is enabled,
        // Export cannot turn disabled again, so this never fails by timing alone.
        let presetEnabled = app.buttons["Deep Dive"].isEnabled, exportEnabled = app.buttons["Export"].isEnabled
        XCTAssertTrue(!presetEnabled || exportEnabled, "A preset was enabled during the analysis")
        waitUntilEnabled(app.buttons["Export"])
        app.buttons["Deep Dive"].tap()
        app.buttons["Compare"].tap()
        app.buttons["Compare"].tap()
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Photo editor"; screenshot.lifetime = .keepAlways
        add(screenshot)
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
        XCTAssertTrue(app.selectPhotoButton.waitForExistence(timeout: 10))
        app.selectPhotoButton.tap()
        let cell = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        // A freshly booted simulator shows "Loading…" in the picker for longer than 8 s.
        XCTAssertTrue(cell.waitForExistence(timeout: 30))
        cell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.confirmPhotoPicker()
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
    /// Export, the presets and Compare stay disabled until the analysis ends. A tap before that does nothing.
    @MainActor
    private func waitUntilEnabled(_ element: XCUIElement) {
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 60), .completed, "\(element) stayed disabled")
    }
    /// Taps Export in the options sheet. Its identifier tells it apart from the editor's Export behind the sheet.
    @MainActor
    private func tapSheetExport(_ app: XCUIApplication) {
        let start = app.buttons["export-confirm"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
    }
    /// A first install takes its 3 welcome photos in one batch, with the mark. After that Home offers one photo
    /// again (Jake, 4 Nov 2026). Saves 3 photos to the simulator library.
    @MainActor
    func testFreeFirstInstallSavesThreePhotosInOneBatch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-keychain=\(UUID().uuidString)", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let select = app.buttons["Select Photos"]
        XCTAssertTrue(select.waitForExistence(timeout: 10), "A first install should offer 3 photos")
        select.tap()
        let cells = app.images.matching(identifier: "PXGGridLayout-Info")
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 30), "Picker contents: \(app.debugDescription)")
        for index in 0..<3 { cells.element(boundBy: index).tap() }
        app.confirmPhotoPicker()
        let saveAll = app.buttons["Save All (3)"]
        XCTAssertTrue(saveAll.waitForExistence(timeout: 60), "Batch screen did not load 3 photos")
        waitUntilEnabled(saveAll)
        XCTAssertTrue(app.staticTexts["Free export with an UnderBlue watermark."].exists)
        saveAll.tap()
        let summary = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Saved to Photos'")).firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 120), "No save summary: \(app.debugDescription)")
        XCTAssertEqual(summary.label, "Saved to Photos: 3")
        app.alerts.buttons["OK"].tap()
        if app.buttons["Not Now"].waitForExistence(timeout: 2) { app.buttons["Not Now"].tap() }
        app.navigationBars.buttons["UnderBlue"].tap()
        XCTAssertTrue(app.buttons["Select Photo"].waitForExistence(timeout: 10), "The welcome photos should be used")
    }
    @MainActor
    func testVideoImportAndLandscapeEditor() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-keychain=\(UUID().uuidString)", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Select Video"].waitForExistence(timeout: 10))
        app.buttons["Select Video"].tap()
        let cell = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 30))
        cell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Compare"].waitForExistence(timeout: 15))
        waitUntilEnabled(app.buttons["Export"])
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
