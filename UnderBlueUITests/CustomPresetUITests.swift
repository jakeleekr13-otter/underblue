import XCTest

/// The Custom preset: its sliders replace intensity, keep their values across launches, and Reset clears them.
final class CustomPresetUITests: XCTestCase {
    private let names = ["Brightness", "Contrast", "Saturation", "Clarity", "Temperature"]

    @MainActor
    func testPhotoCustomSlidersPersistAndReset() throws {
        var app = launch()
        try open(app, button: "Select Photo")
        selectCustom(app)
        for name in names { XCTAssertTrue(app.sliders[name].exists, "missing slider \(name)") }
        XCTAssertFalse(app.sliders["Filter intensity"].exists)
        // Start from zero in case an earlier run left values behind.
        if app.buttons["Reset"].isEnabled { reset(app) }
        XCTAssertFalse(app.buttons["Reset"].isEnabled)
        show(app.sliders["Brightness"], in: app)
        app.sliders["Brightness"].adjust(toNormalizedSliderPosition: 0.8)
        let value = app.sliders["Brightness"].value as? String ?? ""
        XCTAssertTrue(value.hasPrefix("+"), "Brightness value \(value)")
        XCTAssertTrue(app.buttons["Reset"].isEnabled)
        attach(app, "custom-photo")

        // The one saved slot comes back after a relaunch.
        app.terminate()
        app = launch()
        try open(app, button: "Select Photo")
        selectCustom(app)
        XCTAssertEqual(app.sliders["Brightness"].value as? String, value)
        reset(app, confirm: false)
        XCTAssertEqual(app.sliders["Brightness"].value as? String, value, "Cancel in the dialog keeps the values")
        reset(app)
        XCTAssertEqual(app.sliders["Brightness"].value as? String, "0")
        XCTAssertFalse(app.buttons["Reset"].isEnabled)
        // Built-in presets keep the intensity slider.
        app.buttons["Deep Dive"].tap()
        XCTAssertTrue(app.sliders["Filter intensity"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.sliders["Brightness"].exists)
    }

    @MainActor
    func testVideoCustomSliders() throws {
        let app = launch()
        try open(app, button: "Select Video")
        selectCustom(app)
        for name in names { XCTAssertTrue(app.sliders[name].exists, "missing slider \(name)") }
        XCTAssertFalse(app.sliders["Filter intensity"].exists)
        show(app.sliders["Temperature"], in: app)
        app.sliders["Temperature"].adjust(toNormalizedSliderPosition: 0.25)
        XCTAssertTrue((app.sliders["Temperature"].value as? String ?? "").hasPrefix("-"))
        attach(app, "custom-video")
        reset(app)
        XCTAssertEqual(app.sliders["Temperature"].value as? String, "0")
    }

    @MainActor private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-keychain=custom-preset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    @MainActor private func open(_ app: XCUIApplication, button: String) throws {
        let opener = button == "Select Photo" ? app.selectPhotoButton : app.buttons[button]
        XCTAssertTrue(opener.waitForExistence(timeout: 10))
        opener.tap()
        let cell = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        // A freshly booted simulator shows "Loading…" in the picker for longer than 8 s.
        if !cell.waitForExistence(timeout: 30), app.staticTexts["No Videos"].exists { throw XCTSkip("No videos in this library") }
        guard cell.exists else { XCTFail("Picker contents: \(app.debugDescription)"); return }
        cell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        if button == "Select Photo" { app.confirmPhotoPicker() }
        // Wait until the media is open, so the controls act on a loaded editor.
        let export = app.buttons["Export"]
        XCTAssertTrue(export.waitForExistence(timeout: 30))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: export)
        waitForExpectations(timeout: 60)
    }

    /// Reset asks first (flow review 6.12). On iOS 27 the dialog is a popover over Reset with its own Reset button
    /// (the last one in the tree) and no Cancel: a tap outside closes it.
    @MainActor private func reset(_ app: XCUIApplication, confirm: Bool = true) {
        app.buttons["Reset"].firstMatch.tap()
        let title = app.staticTexts["Reset all Custom sliders to 0?"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "Reset did not ask")
        if confirm {
            let buttons = app.buttons.matching(identifier: "Reset")
            buttons.element(boundBy: buttons.count - 1).tap()
        } else if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].tap()
        } else {
            app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        // Wait until the dialog is gone, so later queries find one Reset button.
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: title)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed, "the Reset dialog stayed open")
    }
    /// A tap scrolls the capped controls area, but `adjust` does not. Drag on the label row above a visible
    /// slider (not on a slider) until this one is on screen.
    @MainActor private func show(_ slider: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 where !slider.isHittable {
            guard let anchor = app.sliders.allElementsBoundByIndex.first(where: { $0.isHittable }) else { return }
            let start = anchor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -0.8))
            let down = slider.frame.minY < anchor.frame.minY
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: down ? 250 : -250)))
        }
    }

    /// Custom is the last tile, so on a narrow screen the strip may need a swipe first.
    @MainActor private func selectCustom(_ app: XCUIApplication) {
        let custom = app.buttons["Custom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        if custom.frame.maxX > app.frame.maxX { app.buttons["Tropical"].swipeLeft() }
        custom.tap()
        XCTAssertTrue(app.sliders["Brightness"].waitForExistence(timeout: 5))
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
}
