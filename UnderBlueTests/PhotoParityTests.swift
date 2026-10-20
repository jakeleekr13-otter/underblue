import XCTest
@testable import UnderBlue

/// Exports photos with the app's photo path, so the files can be compared with the Mac app's export of the same photos.
/// It prints and asserts nothing. It is skipped unless the input folder exists.
/// - On a device the folder is Documents/parity-in in the app's container (copy it there with `devicectl device copy to`).
/// - On the simulator set UB_PARITY_IN (and optionally UB_PARITY_OUT) as TEST_RUNNER_UB_PARITY_IN.
/// Results go to the output folder as `<name>_ios.jpg`.
final class PhotoParityTests: XCTestCase {
    /// Removes the parity folders from the app's Documents. Run it with TEST_RUNNER_UB_PARITY_CLEAN=1 after a device check.
    func testRemoveParityFolders() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["UB_PARITY_CLEAN"] == "1", "UB_PARITY_CLEAN is not set")
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for name in ["parity-in", "parity-out"] { try? FileManager.default.removeItem(at: documents.appendingPathComponent(name)) }
    }

    func testExportPhotosForParityCheck() async throws {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let environment = ProcessInfo.processInfo.environment
        let input = environment["UB_PARITY_IN"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? documents.appendingPathComponent("parity-in")
        let output = environment["UB_PARITY_OUT"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? documents.appendingPathComponent("parity-out")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: input.path), "no parity-in folder")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let files = try FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let processor = PhotoProcessor()
            // The same steps as the batch engine: analyse, then export with the default look (Natural Dive, 0.8).
            var settings = FilterSettings()
            settings.analysis = try await processor.analyze(file)
            let exported = try await processor.export(file, settings: settings, keepHDR: true, format: .jpeg)
            let target = output.appendingPathComponent(file.deletingPathExtension().lastPathComponent + "_ios.jpg")
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: exported, to: target)
            print("PARITY exported \(file.lastPathComponent) -> \(target.lastPathComponent)")
        }
    }
}
