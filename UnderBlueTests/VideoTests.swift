import XCTest
import AVFoundation
import CoreImage
@testable import UnderBlue

final class VideoTests: XCTestCase {
    func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "mov"))
    }
    func testSDRCodecResolutionTimingAudioAndOrientationMatrix() async throws {
        for name in ["h264_1080_30_audio", "hevc_1080_60", "portrait_audio", "hevc_4k_24_audio", "hevc_4k_60"] {
            let url = try fixture(name)
            let metadata = try await MediaInspector().inspect(url)
            let result = try await VideoExporter().export(url: url, metadata: metadata,
                settings: .init(preset: .natural, intensity: 0.8, analysis: .init(redLoss: 0.6)), options: .init()) { _ in }
            defer { TemporaryFiles.remove(result.url) }
            XCTAssertEqual(result.metadata.audioTrackCount, metadata.audioTrackCount, name)
            XCTAssertEqual(result.metadata.displaySize, metadata.displaySize, name)
            XCTAssertEqual(result.metadata.frameRate, metadata.frameRate, accuracy: 0.1, name)
            XCTAssertFalse(result.metadata.isHDR, name)
            XCTAssertEqual(result.metadata.duration, metadata.duration, accuracy: 0.06, name)
        }
    }
    /// The particle filter returns each frame 3 frames later and is flushed at the end (off by default, D2).
    /// With it on, every frame, the size, the frame rate, the duration and the audio must stay as with it off.
    func testParticleRemovalKeepsEveryFrameTimingAndAudio() async throws {
        // Without the filter the "on" export would pass frames straight through and prove nothing.
        XCTAssertNotNil(ParticleFilter(context: CIContext()), "the particle filter's kernels did not build")
        for name in ["h264_1080_30_audio", "portrait_audio"] {
            let url = try fixture(name)
            let metadata = try await MediaInspector().inspect(url)
            let settings = FilterSettings(preset: .natural, intensity: 0.8, analysis: .init(redLoss: 0.6))
            let off = try await VideoExporter(removesParticles: false).export(url: url, metadata: metadata, settings: settings, options: .init()) { _ in }
            defer { TemporaryFiles.remove(off.url) }
            let on = try await VideoExporter(removesParticles: true).export(url: url, metadata: metadata, settings: settings, options: .init()) { _ in }
            defer { TemporaryFiles.remove(on.url) }
            XCTAssertEqual(on.frames, off.frames, name)
            XCTAssertEqual(on.metadata.displaySize, off.metadata.displaySize, name)
            XCTAssertEqual(on.metadata.audioTrackCount, metadata.audioTrackCount, name)
            XCTAssertEqual(on.metadata.frameRate, metadata.frameRate, accuracy: 0.1, name)
            XCTAssertEqual(on.metadata.duration, off.metadata.duration, accuracy: 0.001, name)
        }
    }
    func testExportedPortraitPixelsMatchSourceOrientation() async throws {
        let url = try fixture("portrait_audio")
        let metadata = try await MediaInspector().inspect(url)
        let result = try await VideoExporter().export(url: url, metadata: metadata, settings: .init(preset: .original), options: .init()) { _ in }
        defer { TemporaryFiles.remove(result.url) }
        func pixels(_ url: URL) async throws -> [Float] {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            let cg = try await generator.image(at: .zero).image
            let image = CIImage(cgImage: cg).transformed(by: CGAffineTransform(scaleX: 16 / Double(cg.width), y: 16 / Double(cg.height)))
            var values = [Float](repeating: 0, count: 16 * 16 * 4)
            FilterEngine().context.render(image, toBitmap: &values, rowBytes: 16 * 16, bounds: CGRect(x: 0, y: 0, width: 16, height: 16), format: .RGBAf, colorSpace: FilterEngine.workingSpace)
            return values
        }
        let source = try await pixels(url), exported = try await pixels(result.url)
        let meanError = zip(source, exported).reduce(Float(0)) { $0 + abs($1.0 - $1.1) } / Float(source.count)
        XCTAssertLessThan(meanError, 0.04, "Portrait pixels are rotated or mirrored incorrectly")
    }
    func testTrialVideoStopsAtTenSecondsAndKeepsAudio() async throws {
        let url = try fixture("trial_12seconds")
        let metadata = try await MediaInspector().inspect(url)
        let result = try await VideoExporter().export(url: url, metadata: metadata, settings: .init(),
            options: .init(resolution: .hd, durationLimit: 10)) { _ in }
        defer { TemporaryFiles.remove(result.url) }
        XCTAssertEqual(result.metadata.duration, 10, accuracy: 0.04)
        XCTAssertEqual(result.frames, 300)
        XCTAssertEqual(result.metadata.audioTrackCount, 1)
    }
    func testVariablePresentationTimesArePreserved() async throws {
        let url = try fixture("variable_timing")
        let metadata = try await MediaInspector().inspect(url)
        let result = try await VideoExporter().export(url: url, metadata: metadata, settings: .init(), options: .init()) { _ in }
        defer { TemporaryFiles.remove(result.url) }
        func times(_ url: URL) async throws -> [Double] {
            let asset = AVURLAsset(url: url)
            let track = try await asset.loadTracks(withMediaType: .video)[0]
            let reader = try AVAssetReader(asset: asset)
            let samples = reader.outputProvider(for: AVAssetReaderTrackOutput(track: track, outputSettings: nil))
            try reader.start()
            var times: [Double] = []
            while let sample = try await samples.next() {
                // Container marker buffers carry no media samples and can have invalid/rounded time.
                if sample.sampleCount > 0 { times.append(sample.presentationTimeStamp.seconds) }
            }
            return times.sorted()
        }
        let source = try await times(url), exported = try await times(result.url)
        XCTAssertEqual(source.count, exported.count)
        for (a, b) in zip(source, exported) { XCTAssertEqual(a, b, accuracy: 0.0001) }
    }
    /// A 59.94 fps clip whose last frame starts 38/60000 s before the end, like the
    /// 2019-05-05 dive clip that failed the device export. Rounded to 1/600 s, that
    /// frame lands on the end of the edit, so the export holds it but never shows it.
    func testLastFrameJustBeforeTheEndIsShown() async throws {
        let url = try TemporaryFiles.makeURL(extension: "mov")
        defer { TemporaryFiles.remove(url) }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 320, AVVideoHeightKey: 180])
        input.mediaTimeScale = 60000
        writer.movieTimeScale = 60000
        let receiver = writer.inputPixelBufferReceiver(for: input, pixelBufferAttributes: try XCTUnwrap(CVPixelBufferCreationAttributes(
            CVPixelBufferAttributes(rawAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                                                    kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180]))))
        try writer.start()
        writer.startSession(atSourceTime: .zero)
        let frames = 60
        for index in 0..<frames {
            let frame = try XCTUnwrap(receiver.pixelBufferPool).makeMutablePixelBuffer()
            frame.withUnsafeBuffer { buffer in
                CVPixelBufferLockBaseAddress(buffer, [])
                memset(CVPixelBufferGetBaseAddress(buffer), Int32(40 + index), CVPixelBufferGetDataSize(buffer))
                CVPixelBufferUnlockBaseAddress(buffer, [])
            }
            try await receiver.append(CVReadOnlyPixelBuffer(frame), with: CMTime(value: CMTimeValue(index * 1001), timescale: 60000))
        }
        receiver.finish()
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue((frames - 1) * 1001 + 38), timescale: 60000))
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)

        let metadata = try await MediaInspector().inspect(url)
        let result = try await VideoExporter().export(url: url, metadata: metadata, settings: .init(preset: .original), options: .init()) { _ in }
        defer { TemporaryFiles.remove(result.url) }
        XCTAssertEqual(result.frames, frames)
        // Decoding skips a frame outside the edit, so it counts the frames a player shows.
        let asset = AVURLAsset(url: result.url)
        let reader = try AVAssetReader(asset: asset)
        let decoded = reader.outputProvider(for: AVAssetReaderTrackOutput(track: try await asset.loadTracks(withMediaType: .video)[0],
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]))
        try reader.start()
        var shown = 0
        while let sample = try await decoded.next() { shown += sample.sampleCount }
        XCTAssertEqual(shown, frames)
    }
    func testMidExportCancellationCleansPartialFile() async throws {
        let url = try fixture("trial_12seconds")
        let metadata = try await MediaInspector().inspect(url)
        let before = Set((try? FileManager.default.contentsOfDirectory(atPath: TemporaryFiles.directory.path)) ?? [])
        let task = Task {
            try await VideoExporter().export(url: url, metadata: metadata, settings: .init(), options: .init()) { fraction in
                if fraction > 0.1 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        do { _ = try await task.value; XCTFail("Cancellation did not stop export") } catch is CancellationError { }
        let after = Set((try? FileManager.default.contentsOfDirectory(atPath: TemporaryFiles.directory.path)) ?? [])
        XCTAssertEqual(before, after)
    }
    func testLowerResolutionIsNeverUpscaled() {
        let options = ExportOptions(resolution: .hd)
        XCTAssertEqual(options.size(for: CGSize(width: 640, height: 480)), CGSize(width: 640, height: 480))
        XCTAssertEqual(options.size(for: CGSize(width: 2160, height: 3840)), CGSize(width: 1080, height: 1920))
    }
    func testCancellationLeavesNoPartialOutput() async throws {
        let url = try fixture("hevc_4k_60")
        let metadata = try await MediaInspector().inspect(url)
        let before = Set((try? FileManager.default.contentsOfDirectory(atPath: TemporaryFiles.directory.path)) ?? [])
        let task = Task {
            try await VideoExporter().export(url: url, metadata: metadata, settings: .init(), options: .init()) { _ in }
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled export succeeded") } catch is CancellationError { }
        let after = Set((try? FileManager.default.contentsOfDirectory(atPath: TemporaryFiles.directory.path)) ?? [])
        XCTAssertEqual(before, after)
    }
}
