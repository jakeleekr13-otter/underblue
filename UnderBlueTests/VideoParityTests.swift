import XCTest
@testable import UnderBlue

/// Exports videos with the app's video path, so the files can be compared with the Mac render of the same clips,
/// or with an export of another build (the reader/writer API move, 27 Oct 2026). It is skipped unless the input folder exists.
/// - On a device the folder is Documents/parity-in-video in the app's container (copy it there with `devicectl device copy to`).
/// Results go to Documents/parity-out-video as `<name>_sdr.mov`, and `<name>_hdr.mov` for an HDR source.
/// The scene timeline and each export's time are printed.
final class VideoParityTests: XCTestCase {
    func testExportVideosForParityCheck() async throws {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        // UB_PARITY_DIR (TEST_RUNNER_UB_PARITY_DIR) picks another input folder, for a speed run on one clip.
        let input = documents.appendingPathComponent(ProcessInfo.processInfo.environment["UB_PARITY_DIR"] ?? "parity-in-video")
        let output = documents.appendingPathComponent("parity-out-video")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: input.path), "no parity-in-video folder")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let files = try FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(files.isEmpty)
        for file in files {
            // The same steps as the editor: analyse the scenes, then export with the default look.
            let metadata = try await MediaInspector().inspect(file)
            print("PARITY thermal before \(file.lastPathComponent): \(ProcessInfo.processInfo.thermalState.rawValue)")
            let analysisStart = Date()
            let analysis = try await VideoRestorationAnalyzer().analyze(url: file, metadata: metadata)
            print(String(format: "PARITY analysis %.2f s", Date().timeIntervalSince(analysisStart)))
            for scene in analysis.scenes {
                let m = scene.analysis.meanColor
                print(String(format: "PARITY scene %.2f-%.2f s mean=(%.4f,%.4f,%.4f) mid=%.4f planConf=%.3f",
                             scene.start, scene.end, m.x, m.y, m.z, scene.analysis.midLuminance, scene.plan.confidence))
            }
            var settings = FilterSettings()
            settings.analysis = analysis.legacyAnalysis
            var ranges: [ExportOptions.Range] = [.sdr]
            if metadata.hdrExportable { ranges.append(.hdr) }
            for range in ranges {
                var options = ExportOptions()
                options.range = range
                let result = try await VideoExporter().export(url: file, metadata: metadata, settings: settings,
                                                              options: options, restorationAnalysis: analysis) { _ in }
                let target = output.appendingPathComponent(file.deletingPathExtension().lastPathComponent + "_\(range.rawValue.lowercased()).mov")
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.moveItem(at: result.url, to: target)
                print(String(format: "PARITY exported %@ -> %@: %d frames, %.2f s (frame loop %.2f s), thermal %d", file.lastPathComponent,
                             target.lastPathComponent, result.frames, result.elapsedSeconds, result.frameLoopSeconds,
                             ProcessInfo.processInfo.thermalState.rawValue))
            }
        }
    }
}
