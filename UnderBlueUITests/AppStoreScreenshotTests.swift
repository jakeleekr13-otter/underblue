import XCTest

final class AppStoreScreenshotTests: XCTestCase {
    @MainActor
    func testPhotoBeforeAndAfter() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-keychain=app-store-screenshots",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["Select Photo"].waitForExistence(timeout: 10))
        app.buttons["Select Photo"].tap()

        let photo = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        // A freshly booted simulator shows "Loading…" in the picker for longer than 8 s.
        guard photo.waitForExistence(timeout: 30) else {
            XCTFail("Photo picker contents: \(app.debugDescription)")
            return
        }
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(app.buttons["Compare"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["Deep Dive"].waitForExistence(timeout: 5))
        waitForAnalysis(app)
        app.buttons["Deep Dive"].tap()
        app.sliders["Filter intensity"].adjust(toNormalizedSliderPosition: 1)
        waitForPreview(app)
        attach(app.screenshot(), named: "photo-after")

        app.buttons["Compare"].tap()
        XCTAssertEqual(app.buttons["Compare"].value as? String, "Original")
        // The zoomable preview is one accessibility element of type Other, not an Image.
        XCTAssertTrue(app.descendants(matching: .any)["Photo preview"].waitForExistence(timeout: 10))
        attach(app.screenshot(), named: "photo-before")
    }

    @MainActor
    func testVideoEditor() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-keychain=app-store-video-screenshot",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["Select Video"].waitForExistence(timeout: 10))
        app.buttons["Select Video"].tap()
        let video = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        guard video.waitForExistence(timeout: 30) else {
            XCTFail("Video picker contents: \(app.debugDescription)")
            return
        }
        video.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(app.buttons["Compare"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["Deep Dive"].waitForExistence(timeout: 5))
        waitForAnalysis(app)
        app.buttons["Deep Dive"].tap()
        app.sliders["Filter intensity"].adjust(toNormalizedSliderPosition: 1)
        waitForPreview(app)
        attach(app.screenshot(), named: "video-after")
        app.buttons["Compare"].tap()
        XCTAssertEqual(app.buttons["Compare"].value as? String, "Original")
        attach(app.screenshot(), named: "video-before")
    }

    /// Presets, intensity and Compare stay disabled until the analysis ends, as Export does. A tap before that is lost.
    @MainActor
    private func waitForAnalysis(_ app: XCUIApplication) {
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["Export"])
        waitForExpectations(timeout: 60)
    }
    /// The preview renders the new look after the change. Wait until the "Updating preview" spinner is gone.
    @MainActor
    private func waitForPreview(_ app: XCUIApplication) {
        Thread.sleep(forTimeInterval: 1)
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.activityIndicators["Updating preview"])
        waitForExpectations(timeout: 30)
    }
    private func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
