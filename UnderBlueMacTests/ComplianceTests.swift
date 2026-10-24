import XCTest
@testable import UnderBlue

/// Things the Mac App Store and the depth model's license require. They once were missing.
final class ComplianceTests: XCTestCase {
    /// The depth model is under the Apache License 2.0, which asks that a copy ships with the app (Help shows it).
    func testApacheLicenseTextIsBundled() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Apache-2.0", withExtension: "txt"), "Apache-2.0.txt is not in the app")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("Apache License"))
        XCTAssertTrue(text.contains("TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION"))
    }

    /// The Mac app once had no icon at all: the icon set held only an iPhone image.
    /// Since 24 Oct 2026 it uses the shared Icon Composer file, UnderBlue/Resources/AppIcon.icon.
    func testMacAppHasAnIcon() throws {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String, "AppIcon")
        XCTAssertNotNil(Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), "no .icns in the app")
    }

    func testTheModelIsBundledSoTheLicenseApplies() {
        XCTAssertNotNil(Bundle.main.url(forResource: "DepthAnythingV2SmallF16P6", withExtension: "mlmodelc"))
    }
}
