import XCTest

/// Captures the App Store source screens on a device in one language, for scripts/app_store_screenshots.
/// Set SCREENSHOT_LANGUAGE (ko, ja, zh-Hans, zh-Hant, es-ES) with TEST_RUNNER_SCREENSHOT_LANGUAGE on xcodebuild.
/// It never opens the photo picker, so no photo library appears. For the photo and video screens, the Mac first
/// copies the file into the app's Documents (devicectl), and `--ui-test-open` opens it (Debug builds only).
/// It uses the app's current state (Pro, trial), so the screens match a normal launch.
final class LocalizedScreenshotTests: XCTestCase {
    private struct Labels {
        let locale: String
        let compare: String
        let naturalDive: String
        let original: String
        let export: String
        let selectVideo: String
    }

    /// From UnderBlue/Resources/Localizable.xcstrings.
    private static let labels: [String: Labels] = [
        "ko": Labels(locale: "ko_KR", compare: "비교", naturalDive: "내추럴 다이브", original: "원본", export: "내보내기", selectVideo: "동영상 선택"),
        "ja": Labels(locale: "ja_JP", compare: "比較", naturalDive: "ナチュラルダイブ", original: "オリジナル", export: "書き出す", selectVideo: "ビデオを選択"),
        "zh-Hans": Labels(locale: "zh_CN", compare: "对比", naturalDive: "自然潜水", original: "原始", export: "导出", selectVideo: "选择视频"),
        "zh-Hant": Labels(locale: "zh_TW", compare: "比較", naturalDive: "自然潛水", original: "原始", export: "匯出", selectVideo: "選擇影片"),
        // The app catalog is "es"; an es-ES device resolves to it.
        "es-ES": Labels(locale: "es_ES", compare: "Comparar", naturalDive: "Buceo natural", original: "Original", export: "Exportar", selectVideo: "Seleccionar vídeo"),
    ]

    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testHome() throws {
        let (app, labels) = try launch()
        XCTAssertTrue(app.buttons[labels.selectVideo].waitForExistence(timeout: 15))
        sleep(1)
        attach(app.screenshot(), named: "home")
    }

    /// Documents/photo.jpg must be on the iPhone before this runs.
    @MainActor
    func testPhoto() throws { try captureEditor(named: "photo", file: "photo.jpg") }

    /// Documents/video.mov must be on the iPhone before this runs.
    @MainActor
    func testVideo() throws { try captureEditor(named: "video", file: "video.mov") }

    @MainActor
    private func captureEditor(named name: String, file: String) throws {
        let (app, labels) = try launch(["--ui-test-open=" + file])
        let compare = app.buttons[labels.compare]
        XCTAssertTrue(compare.waitForExistence(timeout: 60), "The editor did not open. Is Documents/\(file) on the iPhone?")
        app.buttons[labels.naturalDive].tap()
        // Export turns on when the analysis is done.
        let export = app.buttons[labels.export]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: export)
        waitForExpectations(timeout: 120)
        sleep(2)
        attach(app.screenshot(), named: name + "_after")
        compare.tap()
        XCTAssertEqual(compare.value as? String, labels.original)
        sleep(2)
        attach(app.screenshot(), named: name + "_before")
    }

    @MainActor
    private func launch(_ arguments: [String] = []) throws -> (XCUIApplication, Labels) {
        let language = ProcessInfo.processInfo.environment["SCREENSHOT_LANGUAGE"] ?? ""
        let labels = try XCTUnwrap(Self.labels[language], "Set SCREENSHOT_LANGUAGE to one of \(Self.labels.keys.sorted())")
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", labels.locale] + arguments
        app.launch()
        return (app, labels)
    }

    private func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
