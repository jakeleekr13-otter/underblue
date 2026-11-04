import XCTest
import CoreImage
@testable import UnderBlue

/// A failed open shows its reason with Try again, and Try again opens the media once it can be read
/// (flow review 6.11, 4 Nov 2026). Before, a failed open left a black preview and no way to retry.
@MainActor
final class EditorLoadTests: XCTestCase {
    func testFailedOpenShowsTheReasonAndTryAgainOpens() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("EditorLoad-\(UUID().uuidString).heic")
        defer { try? FileManager.default.removeItem(at: url) }
        let diagnostics = DiagnosticRecorder(directory: FileManager.default.temporaryDirectory.appendingPathComponent("EditorLoadDiag-\(UUID().uuidString)"))
        let model = EditorModel(media: ImportedMedia(url: url, kind: .photo), diagnostics: diagnostics)
        await model.load()
        XCTAssertNotNil(model.loadFailure, "a missing file must not leave a silent black preview")
        XCTAssertFalse(model.ready); XCTAssertFalse(model.loading)
        XCTAssertNil(model.error, "the reason shows in place, not also as an alert")

        let image = CIImage(color: CIColor(red: 0.1, green: 0.5, blue: 0.6)).cropped(to: CGRect(x: 0, y: 0, width: 800, height: 600))
        try FilterEngine().context.writeHEIFRepresentation(of: image, to: url, format: .RGBA8, colorSpace: FilterEngine.photoSpace)
        await model.retryLoad()
        XCTAssertNil(model.loadFailure)
        XCTAssertTrue(model.ready, "Try again opens the photo")
        XCTAssertNotNil(model.preview)
    }
}
