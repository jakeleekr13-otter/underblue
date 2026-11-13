import XCTest

/// Rotate in the editor: off while the scene is analysed, then each press turns the preview 90° clockwise.
/// Needs a video in the app's Documents, copied there before the run (`simctl get_app_container … data`).
/// The file name comes from `UI_TEST_VIDEO`; without it the test is skipped.
final class VideoRotationUITests: XCTestCase {
    func testRotateTurnsThePreviewAfterAnalysis() throws {
        guard let file = ProcessInfo.processInfo.environment["UI_TEST_VIDEO"] ?? ProcessInfo.processInfo.environment["TEST_RUNNER_UI_TEST_VIDEO"]
        else { throw XCTSkip("set UI_TEST_VIDEO to a file in the app's Documents") }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-keychain=\(UUID().uuidString)", "--ui-test-open=\(file)",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let rotate = app.buttons["Rotate"]
        XCTAssertTrue(rotate.waitForExistence(timeout: 60), "Rotate button missing")
        // Off until the analysis ends.
        let deadline = Date().addingTimeInterval(300)
        while !rotate.isEnabled, Date() < deadline { sleep(1) }
        XCTAssertTrue(rotate.isEnabled, "Rotate stayed off: the analysis did not end in 300 s")
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
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
