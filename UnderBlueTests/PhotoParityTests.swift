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

    /// Prints the analysis and the correction values of every photo in the parity folder. The Mac
    /// harness prints the same fields, so a device reading can be put beside a Mac one. A colour
    /// change that works on the Mac may not work on a phone (docs/MacApp.md). It asserts nothing.
    func testPrintAnalysisForParityPhotos() async throws {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let environment = ProcessInfo.processInfo.environment
        let input = environment["UB_PARITY_IN"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? documents.appendingPathComponent("parity-in")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: input.path), "no parity-in folder")
        let files = try FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let a = try await PhotoProcessor().analyze(file)
            let v = ColorCorrection.make(analysis: a, preset: .natural)
            let neutralChroma = ColorCorrection.oklch(a.neutralColor).y
            let waterChroma = ColorCorrection.oklch(a.waterColor).y
            print("PARITY analysis \(file.lastPathComponent)"
                + " mean=(\(a.meanRed),\(a.meanGreen),\(a.meanBlue))"
                + " water=(\(a.waterRed),\(a.waterGreen),\(a.waterBlue))"
                + " neutral=(\(a.neutralRed),\(a.neutralGreen),\(a.neutralBlue))"
                + " share=\(a.neutralShare) mid=\(a.midLuminance)"
                + " waterChroma=\(waterChroma) neutralChroma=\(neutralChroma)"
                + " type=\(v.waterType)"
                + " neutralGains=(\(v.neutralGains.x),\(v.neutralGains.y),\(v.neutralGains.z))"
                + " refStrength=\(v.referenceStrength)"
                + " refGains=(\(v.referenceGains.x),\(v.referenceGains.y),\(v.referenceGains.z))")
        }
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
