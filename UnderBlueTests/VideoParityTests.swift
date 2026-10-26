import XCTest
@testable import UnderBlue

/// Exports videos with the app's video path, so the files can be compared with the Mac render of the same clips.
/// It is skipped unless the input folder exists.
/// - On a device the folder is Documents/parity-in-video in the app's container (copy it there with `devicectl device copy to`).
/// Results go to Documents/parity-out-video as `<name>_ios.mov`. The scene timeline is printed.
final class VideoParityTests: XCTestCase {
    func testExportVideosForParityCheck() async throws {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let input = documents.appendingPathComponent("parity-in-video")
        let output = documents.appendingPathComponent("parity-out-video")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: input.path), "no parity-in-video folder")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let files = try FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(files.isEmpty)
        for file in files {
            // The same steps as the editor: analyse the scenes, then export with the default look.
            let metadata = try await MediaInspector().inspect(file)
            let engine = FilterEngine()
            let trackStart = Date()
            let track = try await VideoColourTrack.measure(url: file, duration: metadata.videoDuration, context: engine.context, frame: nil)
            print(String(format: "PARITY colour track %.2f s, %d frames", Date().timeIntervalSince(trackStart), track?.times.count ?? 0))
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
            let result = try await VideoExporter().export(url: file, metadata: metadata, settings: settings,
                                                          options: .init(), restorationAnalysis: analysis) { _ in }
            let target = output.appendingPathComponent(file.deletingPathExtension().lastPathComponent + "_ios.mov")
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: result.url, to: target)
            print("PARITY exported \(file.lastPathComponent) -> \(target.lastPathComponent)")
        }
    }
}
