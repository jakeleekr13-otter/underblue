import XCTest

/// Needs a Pro device or account: the picker allows several photos only for Pro.
final class BatchFlowTests: XCTestCase {
    @MainActor
    func testBatchSelectCompareOverrideAndSave() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-keychain=batch-flow", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        addUIInterruptionMonitor(withDescription: "Photos access") { alert in
            for label in ["Allow Full Access", "Allow", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap(); return true
            }
            return false
        }
        app.launch()

        let select = app.buttons["Select Photos"]
        guard select.waitForExistence(timeout: 10) else {
            throw XCTSkip("Not Pro: Home shows no multi-photo picker")
        }
        select.tap()
        let cells = app.images.matching(identifier: "PXGGridLayout-Info")
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 15), "Picker contents: \(app.debugDescription)")
        cells.element(boundBy: 0).tap()
        cells.element(boundBy: 1).tap()
        let add = ["Add", "Done"].map { app.buttons[$0] }.first { $0.exists }
        guard let add else { XCTFail("No picker confirm button: \(app.debugDescription)"); return }
        add.tap()

        let saveAll = app.buttons["Save All (2)"]
        XCTAssertTrue(saveAll.waitForExistence(timeout: 60), "Batch screen did not load 2 photos")
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: saveAll)
        waitForExpectations(timeout: 60)
        attach(app, "1-grid")

        app.buttons["Compare"].tap()
        attach(app, "2-grid-original")
        app.buttons["Compare"].tap()

        app.buttons["Deep Dive"].firstMatch.tap()
        sleep(2)
        attach(app, "3-grid-deep")

        // Open the first photo, swipe to the second, give it its own look, then reset it.
        app.descendants(matching: .any).matching(identifier: "Corrected").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["1 of 2"].waitForExistence(timeout: 10))
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["2 of 2"].waitForExistence(timeout: 5))
        app.buttons["Tropical"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Reset to batch settings"].waitForExistence(timeout: 5))
        sleep(2)
        attach(app, "4-detail-override")
        app.buttons["Reset to batch settings"].tap()
        XCTAssertFalse(app.buttons["Reset to batch settings"].exists)
        app.buttons["Tropical"].firstMatch.tap()
        app.buttons["Done"].tap()

        saveAll.tap()
        app.tap() // lets the interruption monitor handle a Photos permission alert
        let summary = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Saved to Photos'")).firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 120), "No save summary")
        attach(app, "5-saved")
        XCTAssertEqual(summary.label, "Saved to Photos: 2")
    }

    /// Needs Pro (a sandbox purchase on a device). With add access denied, Save All shows the access alert at
    /// once and renders nothing. Before 4 Nov 2026 it rendered every photo, failed each save, then showed a
    /// "Saved to Photos: 0 of 3" summary (flow review 6.5). Nothing reaches the library, because access is denied.
    @MainActor
    func testSaveAllWithPhotosAccessDeniedStopsBeforeRendering() throws {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .photos)
        // Leave the next save to ask again, instead of leaving access denied on the device.
        addTeardownBlock { @MainActor in app.resetAuthorizationStatus(for: .photos) }
        app.launchArguments = ["--ui-test-keychain=batch-denied", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let select = app.buttons["Select Photos"]
        guard select.waitForExistence(timeout: 10) else { throw XCTSkip("Not Pro: Home shows no multi-photo picker") }
        select.tap()
        let cells = app.images.matching(identifier: "PXGGridLayout-Info")
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 30), "Picker contents: \(app.debugDescription)")
        for index in 0..<3 { cells.element(boundBy: index).tap() }
        let add = ["Add", "Done"].map { app.buttons[$0] }.first { $0.exists }
        guard let add else { XCTFail("No picker confirm button: \(app.debugDescription)"); return }
        add.tap()
        let saveAll = app.buttons["Save All (3)"]
        XCTAssertTrue(saveAll.waitForExistence(timeout: 60), "Batch screen did not load 3 photos")
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: saveAll)
        waitForExpectations(timeout: 120)
        saveAll.tap()
        // The system asks for add access in the device language. "Don't Allow" is the first button.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let prompt = springboard.alerts.firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 15), "No Photos access prompt")
        attach(app, "1-access-prompt")
        prompt.buttons.element(boundBy: 0).tap()
        let denied = app.staticTexts["Allow UnderBlue to add to Photos in Settings, then try saving again."]
        XCTAssertTrue(denied.waitForExistence(timeout: 10), "No access alert: \(app.debugDescription)")
        attach(app, "2-access-alert")
        XCTAssertTrue(app.alerts.buttons["Open Settings"].exists, "The access alert should open Settings (flow review 6.14)")
        app.alerts.buttons["OK"].tap()
        let summary = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Saved to Photos'")).firstMatch
        XCTAssertFalse(summary.waitForExistence(timeout: 20), "The batch ran after access was denied")
        XCTAssertTrue(saveAll.exists, "Save All should still offer all 3 photos")
    }

    /// Needs Pro on a device. A single export with add access denied: the save alert offers Open Settings and the
    /// finished file stays (flow review 6.14). Nothing reaches the library, because access is denied.
    @MainActor
    func testSingleSaveWithPhotosAccessDeniedOffersSettings() throws {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .photos)
        addTeardownBlock { @MainActor in app.resetAuthorizationStatus(for: .photos) }
        app.launchArguments = ["--ui-test-keychain=single-denied", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let select = app.buttons["Select Photos"]
        guard select.waitForExistence(timeout: 10) else { throw XCTSkip("Not Pro: Home shows no multi-photo picker") }
        select.tap()
        let cell = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 30), "Picker contents: \(app.debugDescription)")
        cell.tap()
        let add = ["Add", "Done"].map { app.buttons[$0] }.first { $0.exists }
        guard let add else { XCTFail("No picker confirm button: \(app.debugDescription)"); return }
        add.tap()
        let export = app.buttons["Export"]
        XCTAssertTrue(export.waitForExistence(timeout: 30))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: export)
        waitForExpectations(timeout: 120)
        export.tap()
        let confirm = app.buttons["export-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()
        XCTAssertTrue(app.buttons["Save to Photos"].waitForExistence(timeout: 120))
        app.buttons["Save to Photos"].tap()
        let prompt = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 15), "No Photos access prompt")
        prompt.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.alerts["Couldn’t save"].waitForExistence(timeout: 10), "No save alert: \(app.debugDescription)")
        attach(app, "single-access-alert")
        XCTAssertTrue(app.alerts.buttons["Open Settings"].exists, "The access alert should open Settings")
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.buttons["Save to Photos"].exists, "The finished file stays for a second try")
        app.buttons["Discard"].tap()
        let discard = app.buttons["Discard export"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5)); discard.tap()
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
}
