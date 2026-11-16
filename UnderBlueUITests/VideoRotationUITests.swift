import XCTest

/// Rotate in the editor: hidden while the scene is analysed, then on the preview's top right. Each press turns 90° clockwise.
/// Needs a video in the app's Documents, copied there before the run (`simctl get_app_container … data`).
/// The file name comes from `UI_TEST_VIDEO`; without it the test is skipped.
/// `UI_TEST_LANDSCAPE=1` runs it with the phone turned to landscape (the editor then uses the side panel).
final class VideoRotationUITests: XCTestCase {
    @MainActor
    func testRotateTurnsThePreviewAfterAnalysis() throws {
        guard let file = ProcessInfo.processInfo.environment["UI_TEST_VIDEO"] ?? ProcessInfo.processInfo.environment["TEST_RUNNER_UI_TEST_VIDEO"]
        else { throw XCTSkip("set UI_TEST_VIDEO to a file in the app's Documents") }
        let landscape = (ProcessInfo.processInfo.environment["UI_TEST_LANDSCAPE"] ?? ProcessInfo.processInfo.environment["TEST_RUNNER_UI_TEST_LANDSCAPE"]) == "1"
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-keychain=\(UUID().uuidString)", "--ui-test-open=\(file)",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let rotate = app.buttons["Rotate"]
        // Hidden until the analysis ends, then on the preview's top right.
        XCTAssertTrue(rotate.waitForExistence(timeout: 300), "Rotate did not show: the analysis did not end in 300 s")
        XCTAssertFalse(app.staticTexts["Analyzing…"].exists, "Rotate showed during the analysis")
        let preview = app.otherElements["Video preview"]
        XCTAssertGreaterThan(rotate.frame.midX, preview.frame.midX, "Rotate is not on the right")
        XCTAssertLessThan(rotate.frame.midY, preview.frame.midY, "Rotate is not at the top")
        XCTAssertEqual(rotate.value as? String, "0°")
        attach("before")
        rotate.tap()
        XCTAssertEqual(rotate.value as? String, "90°")
        sleep(2)
        attach("after 90")
        for expected in ["180°", "270°", "0°"] {
            rotate.tap()
            XCTAssertEqual(rotate.value as? String, expected)
        }
        sleep(2)
        attach("after 360")
        // The player's own controls show on a tap. Rotate must stay clear of them.
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(1)
        attach("with player controls")
    }

    @MainActor
    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
