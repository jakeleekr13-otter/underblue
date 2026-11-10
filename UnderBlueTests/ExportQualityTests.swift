import XCTest
@testable import UnderBlue

/// Quick (720p, 30 fps), the quality levels and the estimate from a saved speed (Jake, 10 Nov 2026; roadmap 7.1, 7.4).
final class ExportQualityTests: XCTestCase {
    private func options(_ resolution: ExportOptions.Resolution, _ quality: ExportOptions.Quality = .standard) -> ExportOptions {
        var options = ExportOptions()
        options.resolution = resolution
        options.quality = quality
        return options
    }

    func testQuickIsAtMost720pAndNeverEnlarges() {
        XCTAssertEqual(options(.quick).size(for: CGSize(width: 1920, height: 1080)), CGSize(width: 1280, height: 720))
        XCTAssertEqual(options(.quick).size(for: CGSize(width: 3840, height: 2160)), CGSize(width: 1280, height: 720))
        XCTAssertEqual(options(.quick).size(for: CGSize(width: 1182, height: 2560)), CGSize(width: 590, height: 1280))
        XCTAssertEqual(options(.quick).size(for: CGSize(width: 640, height: 360)), CGSize(width: 640, height: 360))
    }

    func testOnlyQuickDropsFramesAndOnlyAbove30fps() {
        let quick = options(.quick)
        XCTAssertEqual(quick.frameStep(sourceRate: 120), 4)
        XCTAssertEqual(quick.frameStep(sourceRate: 119.88), 4)
        XCTAssertEqual(quick.frameStep(sourceRate: 60), 2)
        XCTAssertEqual(quick.frameStep(sourceRate: 59.94), 2)
        XCTAssertEqual(quick.frameStep(sourceRate: 50), 2)
        XCTAssertEqual(quick.frameStep(sourceRate: 30), 1)
        XCTAssertEqual(quick.frameStep(sourceRate: 29.97), 1)
        XCTAssertEqual(quick.frameStep(sourceRate: 24), 1)
        XCTAssertEqual(quick.outputFrameRate(sourceRate: 120), 30, accuracy: 0.001)
        XCTAssertEqual(quick.outputFrameRate(sourceRate: 59.94), 29.97, accuracy: 0.001)
        XCTAssertEqual(quick.outputFrameRate(sourceRate: 50), 25, accuracy: 0.001)
        XCTAssertEqual(options(.source).frameStep(sourceRate: 120), 1)
        XCTAssertEqual(options(.hd).frameStep(sourceRate: 120), 1)
        XCTAssertEqual(ExportOptions.frameRateText(30), "30 fps")
        XCTAssertEqual(ExportOptions.frameRateText(29.97), "29.97 fps")
    }

    func testLimiterKeepsFramesOnATimeGrid() {
        // 60 fps to 30 fps: every 2nd frame.
        var limiter = FrameRateLimiter(sourceRate: 60, step: 2)
        let kept = (0..<12).filter { limiter.keeps(Double($0) / 60) }
        XCTAssertEqual(kept, [0, 2, 4, 6, 8, 10])
        // Jitter of a few milliseconds does not change the choice.
        var jittered = FrameRateLimiter(sourceRate: 60, step: 2)
        let times = [0, 0.0172, 0.0331, 0.0503, 0.0664, 0.0838]
        XCTAssertEqual(times.indices.filter { jittered.keeps(times[$0]) }, [0, 2, 4])
        // A gap in the source restarts the grid, so the next kept frame is a full interval later.
        var gap = FrameRateLimiter(sourceRate: 60, step: 2)
        let gapTimes = [0, 1 / 60.0, 2 / 60.0, 0.5, 0.5 + 1 / 60.0, 0.5 + 2 / 60.0]
        XCTAssertEqual(gapTimes.indices.filter { gap.keeps(gapTimes[$0]) }, [0, 2, 3, 5])
        // Step 1 keeps everything.
        var all = FrameRateLimiter(sourceRate: 30, step: 1)
        XCTAssertTrue((0..<10).allSatisfy { all.keeps(Double($0) / 30) })
    }

    func testStandardIsTheOldBitrateAndTheLevelsScaleIt() {
        let size = CGSize(width: 3840, height: 2160)
        let old = Int(min(100_000_000, max(6_000_000, size.width * size.height * 60 * 0.12)))
        XCTAssertEqual(VideoExporter.bitrate(for: size, frameRate: 60, quality: .standard), old)
        XCTAssertEqual(Double(VideoExporter.bitrate(for: size, frameRate: 60, quality: .high)), Double(old) * 1.5, accuracy: 2)
        XCTAssertEqual(Double(VideoExporter.bitrate(for: size, frameRate: 60, quality: .small)), Double(old) * 0.5, accuracy: 2)
        // The 100 Mbps cap stays.
        XCTAssertEqual(VideoExporter.bitrate(for: size, frameRate: 120, quality: .high), 100_000_000)
        // The 6 Mbps floor is applied before the level, so Small still makes a smaller file at 720p.
        XCTAssertEqual(VideoExporter.bitrate(for: CGSize(width: 1280, height: 720), frameRate: 30, quality: .small), 3_000_000)
    }

    /// Quality depends on the resolution (Jake, 10 Nov 2026): Original High, 1080p Standard, Quick Small, and each
    /// can be changed. A new resolution goes back to its own default.
    func testEachResolutionHasItsOwnDefaultQuality() {
        var options = ExportOptions()
        XCTAssertEqual(options.resolution, .source)
        XCTAssertEqual(options.quality, .high)
        options.quality = .small
        XCTAssertEqual(options.quality, .small)
        options.resolution = .hd
        XCTAssertEqual(options.quality, .standard)
        options.quality = .high
        options.resolution = .quick
        XCTAssertEqual(options.quality, .small)
        options.quality = .high
        XCTAssertEqual(options.quality, .high, "Quick can be changed too")
        options.resolution = .source
        XCTAssertEqual(options.quality, .high)
        XCTAssertEqual(ExportOptions(resolution: .hd).quality, .standard)
    }

    @MainActor func testQuickDetailSays720pUnlessTheSourceIsSmaller() {
        XCTAssertEqual(ExportView.quickDetail(metadata(CGSize(width: 1182, height: 2560), fps: 120, duration: 1)), "720p · 30 fps")
        XCTAssertEqual(ExportView.quickDetail(metadata(CGSize(width: 1920, height: 1080), fps: 59.94, duration: 1)), "720p · 29.97 fps")
        XCTAssertEqual(ExportView.quickDetail(metadata(CGSize(width: 640, height: 360), fps: 24, duration: 1)), "640 × 360 · 24 fps")
    }

    /// The source's average bitrate times the level is the ceiling (Jake, 10 Nov 2026).
    func testBitrateNeverGoesAboveTheSourceTimesTheLevel() {
        let small = CGSize(width: 292, height: 632)
        XCTAssertEqual(VideoExporter.bitrate(for: small, frameRate: 30, quality: .standard, sourceBitRate: 100_952), 100_952)
        XCTAssertEqual(VideoExporter.bitrate(for: small, frameRate: 30, quality: .high, sourceBitRate: 100_952), 151_428)
        XCTAssertEqual(VideoExporter.bitrate(for: small, frameRate: 30, quality: .small, sourceBitRate: 100_952), 50_476)
        // A rich source changes nothing; an unknown one keeps the old rule.
        let fourK = CGSize(width: 3840, height: 2160)
        XCTAssertEqual(VideoExporter.bitrate(for: fourK, frameRate: 30, quality: .standard, sourceBitRate: 200_000_000),
                       VideoExporter.bitrate(for: fourK, frameRate: 30, quality: .standard))
        XCTAssertEqual(VideoExporter.bitrate(for: small, frameRate: 30, quality: .standard, sourceBitRate: nil), 6_000_000)
    }

    func testTrialSetsStandardAndAPurchaseBringsTheQualityBack() {
        var options = options(.source, .high)
        options.applyTrial(true)
        XCTAssertEqual(options.quality, .standard)
        XCTAssertEqual(options.resolution, .hd)
        options.applyTrial(false)
        XCTAssertEqual(options.quality, .high)
        XCTAssertEqual(options.resolution, .source)
    }

    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "mov"))
    }

    func testQuickExportsA60fpsSourceAt30fpsAnd720p() async throws {
        let url = try fixture("hevc_1080_60")
        let source = try await MediaInspector().inspect(url)
        let result = try await VideoExporter().export(url: url, metadata: source, settings: .init(preset: .original),
                                                      options: options(.quick)) { _ in }
        defer { TemporaryFiles.remove(result.url) }
        XCTAssertEqual(result.frames, 18, "36 frames at 60 fps keep every 2nd")
        XCTAssertEqual(result.metadata.displaySize, CGSize(width: 1280, height: 720))
        XCTAssertEqual(result.metadata.frameRate, 30, accuracy: 0.5)
        XCTAssertEqual(result.metadata.duration, source.duration, accuracy: 0.06)
    }

    func testQuickKeepsEveryFrameOfASlowerVariableSource() async throws {
        let url = try fixture("variable_timing")
        let source = try await MediaInspector().inspect(url)
        let result = try await VideoExporter().export(url: url, metadata: source, settings: .init(preset: .original),
                                                      options: options(.quick)) { _ in }
        defer { TemporaryFiles.remove(result.url) }
        XCTAssertEqual(result.frames, 30)
        XCTAssertEqual(result.metadata.displaySize, source.displaySize)
    }

    func testSmallMakesASmallerFileThanHigh() async throws {
        let url = try fixture("hevc_1080_60")
        let source = try await MediaInspector().inspect(url)
        var bytes: [ExportOptions.Quality: Int] = [:]
        for quality in [ExportOptions.Quality.small, .high] {
            let result = try await VideoExporter().export(url: url, metadata: source, settings: .init(preset: .original),
                                                          options: options(.source, quality)) { _ in }
            defer { TemporaryFiles.remove(result.url) }
            bytes[quality] = try XCTUnwrap(try result.url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        }
        let small = try XCTUnwrap(bytes[.small]), high = try XCTUnwrap(bytes[.high])
        XCTAssertLessThan(small, high, "Small \(small) B, High \(high) B")
    }

    private func metadata(_ size: CGSize, fps: Float, duration: Double) -> VideoMetadata {
        VideoMetadata(codec: "hvc1", codedSize: size, displaySize: size, transform: .identity, duration: duration, frameRate: fps,
                      bitDepth: 8, primaries: nil, transfer: nil, matrix: nil, dynamicRange: .sdr,
                      hasDolbyVisionSignaling: false, audioTrackCount: 0)
    }

    func testEstimateIsFramesTimesTheSavedTimePerFrame() throws {
        let source = metadata(CGSize(width: 1920, height: 1080), fps: 60, duration: 10)
        let sample = ExportSpeed.Sample(pixels: 1920 * 1080, secondsPerFrame: 0.04, setupSeconds: 2)
        // Same size: 600 frames × 40 ms + 2 s.
        XCTAssertEqual(try XCTUnwrap(ExportSpeed.estimate(sample, options: options(.source), metadata: source)), 26, accuracy: 0.001)
        // Quick: half the frames at 720p. 40 ms × (0.4 + 0.6 × 0.444) per frame.
        let quick = try XCTUnwrap(ExportSpeed.estimate(sample, options: options(.quick), metadata: source))
        XCTAssertEqual(quick, 2 + 300 * 0.04 * (0.4 + 0.6 * (1280.0 * 720) / (1920 * 1080)), accuracy: 0.001)
        // A free export counts only its first 10 s; a 4K output costs more per frame.
        var free = options(.hd)
        free.durationLimit = 5
        XCTAssertEqual(try XCTUnwrap(ExportSpeed.estimate(sample, options: free, metadata: source)), 14, accuracy: 0.001)
        let fourK = metadata(CGSize(width: 3840, height: 2160), fps: 60, duration: 10)
        XCTAssertGreaterThan(try XCTUnwrap(ExportSpeed.estimate(sample, options: options(.source), metadata: fourK)), 26)
    }

    func testSampleComesFromTheFrameLoop() throws {
        let result = VideoExportResult(url: URL(fileURLWithPath: "/tmp/none.mov"),
                                       metadata: metadata(CGSize(width: 1280, height: 720), fps: 30, duration: 1),
                                       frames: 30, elapsedSeconds: 2.5, frameLoopSeconds: 1.5)
        let sample = try XCTUnwrap(ExportSpeed.Sample(result, outputSize: CGSize(width: 1280, height: 720)))
        XCTAssertEqual(sample.secondsPerFrame, 0.05, accuracy: 0.0001)
        XCTAssertEqual(sample.setupSeconds, 1, accuracy: 0.0001)
        XCTAssertNil(ExportSpeed.Sample(VideoExportResult(url: result.url, metadata: result.metadata, frames: 0,
                                                          elapsedSeconds: 1, frameLoopSeconds: 0), outputSize: CGSize(width: 2, height: 2)))
    }

    func testStoreKeepsOneSampleEachKindAndForgetsAfterAnOSUpdate() throws {
        let suite = "ExportSpeedTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ExportSpeedStore(defaults: defaults, systemMajorVersion: 27)
        let restored = ExportSpeed.Kind(restoration: true, hdr: false), original = ExportSpeed.Kind(restoration: false, hdr: false)
        let sample = ExportSpeed.Sample(pixels: 100, secondsPerFrame: 0.02, setupSeconds: 1)
        XCTAssertNil(store.load(restored))
        store.save(sample, for: restored)
        XCTAssertEqual(store.load(restored), sample)
        XCTAssertNil(store.load(original))
        XCTAssertNil(ExportSpeedStore(defaults: defaults, systemMajorVersion: 28).load(restored))
    }
}
