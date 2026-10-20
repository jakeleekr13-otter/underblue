import XCTest
import Darwin
import Synchronization
@testable import UnderBlue

/// Measures the peak memory of one photo through each stage. It prints numbers and asserts nothing.
/// Set UB_PROFILE_PHOTOS to a colon-separated list of photo paths; without it the test is skipped.
/// Run: TEST_RUNNER_UB_PROFILE_PHOTOS=a.jpg:b.jpg xcodebuild test -only-testing:UnderBlueMacTests/MemoryProfileTests
final class MemoryProfileTests: XCTestCase {
    /// The process footprint in bytes. It counts graphics memory (IOSurface), which RSS does not.
    private static func footprint() -> UInt64 {
        var info = rusage_info_current()
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_CURRENT, $0) }
        }
        return status == 0 ? info.ri_phys_footprint : 0
    }

    /// Runs `work` and returns the highest footprint seen, sampled every 5 ms.
    private func peak<T>(during work: () async throws -> T) async rethrows -> (value: T, peak: UInt64) {
        let highest = Mutex<UInt64>(Self.footprint())
        let sampler = Task.detached {
            while !Task.isCancelled {
                let now = Self.footprint()
                highest.withLock { if now > $0 { $0 = now } }
                try? await Task.sleep(for: .milliseconds(5))
            }
        }
        defer { sampler.cancel() }
        let value = try await work()
        let now = Self.footprint()
        highest.withLock { if now > $0 { $0 = now } }
        return (value, highest.withLock { $0 })
    }

    /// Same measurement for videos: scene analysis, then a full export. Set UB_PROFILE_VIDEOS.
    func testPeakMemoryOfVideoStages() async throws {
        let value = ProcessInfo.processInfo.environment["UB_PROFILE_VIDEOS"] ?? ""
        try XCTSkipIf(value.isEmpty, "UB_PROFILE_VIDEOS is not set")
        let list = value
        for path in list.split(separator: ":").map(String.init) {
            let url = URL(fileURLWithPath: path)
            let metadata = try await MediaInspector().inspect(url)
            let pixels = Double(metadata.displaySize.width * metadata.displaySize.height)
            let base = Self.footprint()
            let analysis = try await peak { try await VideoRestorationAnalyzer().analyze(url: url, metadata: metadata) }
            let afterAnalyze = Self.footprint()
            var settings = FilterSettings(); settings.analysis = analysis.value.legacyAnalysis
            let exporter = VideoExporter()
            let exported = try await peak {
                try await exporter.export(url: url, metadata: metadata, settings: settings, options: ExportOptions(),
                                          restorationAnalysis: analysis.value) { _ in }
            }
            TemporaryFiles.remove(exported.value.url)
            func mb(_ bytes: UInt64) -> String { String(format: "%6.0f MB", Double(bytes) / 1_048_576) }
            print("MEMPROFILE \(url.lastPathComponent) \(Int(metadata.displaySize.width))x\(Int(metadata.displaySize.height)) \(String(format: "%.1f", pixels / 1e6)) MP, \(String(format: "%.1f", metadata.duration)) s"
                  + " | start \(mb(base))"
                  + " | analyze peak +\(mb(analysis.peak - min(analysis.peak, base))), kept after +\(mb(afterAnalyze - min(afterAnalyze, base)))"
                  + " | export peak +\(mb(exported.peak - min(exported.peak, afterAnalyze)))")
        }
    }

    func testPeakMemoryPerStage() async throws {
        let value = ProcessInfo.processInfo.environment["UB_PROFILE_PHOTOS"] ?? ""
        try XCTSkipIf(value.isEmpty, "UB_PROFILE_PHOTOS is not set")
        let list = value
        for path in list.split(separator: ":").map(String.init) {
            let url = URL(fileURLWithPath: path)
            let processor = PhotoProcessor()
            let size = try await processor.preview(url, settings: .init(), original: true, maxPixel: 100_000)
            let pixels = Double(size.width * size.height)
            let base = Self.footprint()
            let analyzed = try await peak { try await processor.analyze(url) }
            let afterAnalyze = Self.footprint()
            var settings = FilterSettings(); settings.analysis = analyzed.value
            let exported = try await peak { try await processor.export(url, settings: settings, keepHDR: true, format: .jpeg) }
            TemporaryFiles.remove(exported.value)
            func mb(_ bytes: UInt64) -> String { String(format: "%6.0f MB", Double(bytes) / 1_048_576) }
            func perPixel(_ bytes: UInt64) -> String { String(format: "%5.1f B/px", Double(bytes) / pixels) }
            print("MEMPROFILE \(url.lastPathComponent) \(size.width)x\(size.height) (\(String(format: "%.1f", pixels / 1e6)) MP)"
                  + " | start \(mb(base))"
                  + " | analyze peak +\(mb(analyzed.peak - min(analyzed.peak, base))) \(perPixel(analyzed.peak - min(analyzed.peak, base))), kept after +\(mb(afterAnalyze - min(afterAnalyze, base)))"
                  + " | export peak +\(mb(exported.peak - min(exported.peak, afterAnalyze))) \(perPixel(exported.peak - min(exported.peak, afterAnalyze)))")
        }
    }
}
