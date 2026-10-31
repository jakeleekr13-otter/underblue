import XCTest
@testable import UnderBlue

final class TemporaryFilesTests: XCTestCase {
    /// An export file left by an ended process goes at the next launch, at any age. Other files keep the 24 h rule.
    func testNewLaunchRemovesExportsAtAnyAgeAndKeepsRecentFiles() throws {
        let export = try TemporaryFiles.makeExportURL(extension: "mov")
        let other = try TemporaryFiles.makeURL(extension: "mov")
        defer { TemporaryFiles.remove(export); TemporaryFiles.remove(other) }
        try Data([1]).write(to: export)
        try Data([1]).write(to: other)
        TemporaryFiles.cleanPreviousSession()
        XCTAssertFalse(FileManager.default.fileExists(atPath: export.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path))
    }
}
