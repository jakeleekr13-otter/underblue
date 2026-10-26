import CoreImage
import Darwin
import XCTest
@testable import UnderBlue

/// Device cost of photo exports (docs/Verification.md): the Labs orb removal (PhotoOrbs), the water core
/// (UnderBlueWaterCore) and large photos (48 MP). It reads the photos in Documents/cost-in, or the folder in UB_COST_DIR
/// (copy them there with `devicectl device copy to`), and is skipped without them. Results go to the console as COST
/// lines. Run on a device with -test-timeouts-enabled: a render that fails can hang for many minutes.
final class PhotoCostProbeTests: XCTestCase {
    private static func footprint() -> UInt64 { FootprintSampler.footprint() }

    /// Runs `body` while a thread samples the footprint every 2 ms. Returns the time and the peak over the start.
    private func measure(_ body: () async throws -> Void) async rethrows -> (ms: Double, peakMB: Double) {
        let sampler = FootprintSampler()
        sampler.begin()
        let t = Date()
        try await body()
        let ms = Date().timeIntervalSince(t) * 1000
        return (ms, sampler.end())
    }

    func testExportCostWithAndWithoutOrbRemoval() async throws {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let input = documents.appendingPathComponent(ProcessInfo.processInfo.environment["UB_COST_DIR"] ?? "cost-in")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: input.path), "no cost-in folder")
        let files = try FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)
            .filter { ["jpg", "jpeg", "heic"].contains($0.pathExtension.lowercased()) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: PhotoOrbs.enabledKey)
        defer { if let saved { defaults.set(saved, forKey: PhotoOrbs.enabledKey) } else { defaults.removeObject(forKey: PhotoOrbs.enabledKey) } }
        for url in files {
            let processor = PhotoProcessor()
            var settings = FilterSettings()
            // Analysis, depth and the plan first, so the exports below measure only what differs.
            settings.analysis = try await processor.analyze(url)
            // Off twice, then on: the first "on" export also finds the orbs, the second reuses them.
            for (label, on) in [("off 1", false), ("off 2", false), ("on 1 (finds)", true), ("on 2 (cached)", true)] {
                defaults.set(on, forKey: PhotoOrbs.enabledKey)
                var output: URL?
                let r = try await measure { output = try await processor.export(url, settings: settings) }
                if let output { try? FileManager.default.removeItem(at: output) }
                print(String(format: "COST export %@ orbs %@: %.0f ms, peak +%.0f MB", url.lastPathComponent, label, r.ms, r.peakMB))
            }
        }
    }

    /// The export of each photo at several Core Image memory targets (UB_COST_LIMITS, MB, "0" = system default).
    func testExportAtMemoryTargets() async throws {
        let env = ProcessInfo.processInfo.environment
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let input = documents.appendingPathComponent(env["UB_COST_DIR"] ?? "cost-in")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: input.path), "no cost-in folder")
        let limits = (env["UB_COST_LIMITS"] ?? "0,768,1024").split(separator: ",").compactMap { Int($0) }
        let files = try FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)
            .filter { ["jpg", "jpeg", "heic"].contains($0.pathExtension.lowercased()) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        print(String(format: "COST footprint at start %.0f MB", Double(Self.footprint()) / 1_048_576))
        // One processor per memory target for every photo, as the editor and the batch keep theirs.
        let processors = Dictionary(uniqueKeysWithValues: limits.map { ($0, PhotoProcessor(memoryLimitMB: $0 > 0 ? $0 : nil)) })
        for url in files {
            for limit in limits {
                let processor = processors[limit]!
                var settings = FilterSettings()
                print(String(format: "COST %@ footprint before analysis %.0f MB", url.lastPathComponent, Double(Self.footprint()) / 1_048_576))
                settings.analysis = try await processor.analyze(url)
                print(String(format: "COST %@ footprint after analysis %.0f MB", url.lastPathComponent, Double(Self.footprint()) / 1_048_576))
                for round in 1...2 {
                    var output: URL?, failure: String?
                    let r: (ms: Double, peakMB: Double) = await measure {
                        let format: ExportOptions.PhotoFormat = env["UB_COST_FORMAT"] == "heic" ? .heic : .jpeg
                        do { output = try await processor.export(url, settings: settings, keepHDR: env["UB_COST_HDR"] == "1", format: format) }
                        catch { failure = "\(error)" }
                    }
                    if let output { try? FileManager.default.removeItem(at: output) }
                    if env["UB_COST_CLEAR"] == "1" {
                        try? await Task.sleep(for: .seconds(1))
                        let before = Double(Self.footprint()) / 1_048_576
                        await processor.clearCaches()
                        try? await Task.sleep(for: .milliseconds(500))
                        print(String(format: "COST clearCaches: %.0f -> %.0f MB", before, Double(Self.footprint()) / 1_048_576))
                    }
                    print(String(format: "COST target %@ %@ round %d: %.0f ms, peak +%.0f MB, footprint after %.0f MB %@", limit > 0 ? "\(limit) MB" : "default",
                                 url.lastPathComponent, round, r.ms, r.peakMB, Double(Self.footprint()) / 1_048_576,
                                 failure.map { "FAILED " + String($0.prefix(120)) } ?? "ok"))
                }
            }
        }
    }

    func testWaterCoreCost() async throws {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let input = documents.appendingPathComponent(ProcessInfo.processInfo.environment["UB_COST_DIR"] ?? "cost-in")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: input.path), "no cost-in folder")
        let files = try FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)
            .filter { ["jpg", "jpeg", "heic"].contains($0.pathExtension.lowercased()) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        // The photo engine, as PhotoProcessor makes it (system memory limit).
        let engine = FilterEngine()
        for url in files {
            guard let raw = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { continue }
            let image = engine.sdr(raw)
            let settings = FilterSettings(preset: .natural, intensity: 0.8, analysis: engine.analyze(image))
            let w = Int(image.extent.width), h = Int(image.extent.height)
            var pixels = [UInt8](repeating: 0, count: w * h * 4)
            // The legacy path (calm, core, colour and the local stages) rendered to pixels, with and without the water core.
            for (label, cores) in [("without", false), ("with", true), ("without", false), ("with", true)] {
                let out = engine.apply(image, settings: settings, coresWater: cores)
                var failure: String?
                let r: (ms: Double, peakMB: Double) = await measure {
                    pixels.withUnsafeMutableBytes { buffer in
                        let destination = CIRenderDestination(bitmapData: buffer.baseAddress!, width: w, height: h, bytesPerRow: w * 4, format: .RGBA8)
                        destination.colorSpace = FilterEngine.photoSpace
                        do {
                            let task = try engine.context.startTask(toRender: out.transformed(by: CGAffineTransform(translationX: -out.extent.minX, y: -out.extent.minY)),
                                                                    to: destination)
                            _ = try task.waitUntilCompleted()
                        } catch { failure = "\(error)" }
                    }
                }
                print(String(format: "COST legacy %@ %dx%d %@ core: %.0f ms, peak +%.0f MB %@", url.lastPathComponent, w, h, label, r.ms, r.peakMB,
                             failure.map { "FAILED " + String($0.prefix(160)) } ?? "ok"))
            }
        }
    }
}
