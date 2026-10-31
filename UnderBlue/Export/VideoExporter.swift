import AVFoundation
import CoreImage
import VideoToolbox
import os

struct VideoExportResult: Sendable {
    let url: URL
    let metadata: VideoMetadata
    let frames: Int
    /// Wall time for the whole export and for the frame loop alone. The difference is fixed setup and checking cost.
    let elapsedSeconds: Double
    let frameLoopSeconds: Double
}

/// Holds a video export between frames while the app is not active. EditorModel sets it.
final class ExportPause: Sendable {
    private struct State { var paused = false, wasPaused = false }
    private let state = OSAllocatedUnfairLock(initialState: State())
    var isPaused: Bool {
        get { state.withLock { $0.paused } }
        set { state.withLock { $0.paused = newValue; $0.wasPaused = $0.wasPaused || newValue } }
    }
    /// True once the export has waited. A writer that fails after that was most likely stopped by iOS.
    var wasPaused: Bool { state.withLock { $0.wasPaused } }
}

actor VideoExporter {
    private let restorationEngine = RestorationEngine()
    private let diagnostics: DiagnosticRecorder?
    /// Marine snow removal (ParticleFilter) before colour. SDR only: HDR was never measured. Off with the Original
    /// preset, which leaves the video as it is. docs/RestorationExperiments.md, D2: after colour it removes 65-87% of
    /// the drifting specks that colour leaves, and keeps 99.9% or more of small subjects.
    /// Off by default (Jake, 26 Oct 2026): on an iPhone 17 it made a 1080p export 70% slower and its peak memory
    /// 449 -> 1023 MB; 4K was 15% slower. It goes on when that cost is down to about +20% time and +100 MB.
    private let removesParticles: Bool
    private let signposter = OSSignposter(subsystem: "com.underblue.app", category: "export")
    #if DEBUG
    private let logger = Logger(subsystem: "com.underblue.app", category: "video-performance")
    #endif

    init(diagnostics: DiagnosticRecorder? = nil, removesParticles: Bool = false) {
        self.diagnostics = diagnostics
        self.removesParticles = removesParticles
    }

    func export(url: URL, metadata: VideoMetadata, settings: FilterSettings, options: ExportOptions,
                restorationAnalysis: VideoRestorationAnalysis? = nil, pause: ExportPause? = nil,
                progress: @escaping @Sendable (Double) async -> Void) async throws -> VideoExportResult {
        let interval = signposter.beginInterval("Video export")
        let startedAt = Date()
        defer { signposter.endInterval("Video export", interval) }
        guard ProcessInfo.processInfo.thermalState != .critical else { throw Failure(kind: .thermal, domain: "UnderBlue", code: 0) }
        try Task.checkCancellation()
        let hdr = options.range == .hdr
        guard !hdr || metadata.hdrExportable else { throw UnderBlueError.unsupported }
        let restoration = settings.preset == .original ? nil : restorationAnalysis
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw UnderBlueError.unreadable }
        let duration = min(metadata.duration, options.durationLimit ?? metadata.duration)
        let size = options.size(for: metadata.displaySize)
        // One Core Image context per export, sized for this output (see memoryLimitMB).
        let engine = FilterEngine(memoryLimitMB: Self.memoryLimitMB(for: size))
        let bitrate = Int(min(100_000_000, max(6_000_000, size.width * size.height * Double(max(24, metadata.frameRate)) * 0.12)))
        try StorageCheck.require(bytes: Int64(Double(bitrate) / 8 * duration * 1.3))
        let target = try TemporaryFiles.makeExportURL(extension: "mov")
        var succeeded = false
        defer { if !succeeded { TemporaryFiles.remove(target) } }
        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: target, fileType: .mov)
        defer {
            if reader.status == .reading { reader.cancelReading() }
            if writer.status == .writing { writer.cancelWriting() }
        }
        let colors = VideoColorPipeline.properties(hdr: hdr, pq: metadata.dynamicRange == .pq)
        let pixelFormat = hdr ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange : kCVPixelFormatType_32BGRA
        // Apple Log is read as decoded 10-bit signal with no colour conversion; AppleLog.decode does the rest.
        let log = metadata.appleLog
        let readFormat = log == nil ? pixelFormat : kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
        let toneMappedByComposition = metadata.isHDR && !hdr && log == nil
        let output: AVAssetReaderOutput
        if toneMappedByComposition {
            // Apple's compositor can tone-map PQ sources that direct decoder pixel transfer rejects.
            // It also matches the editor's SDR preview and retains variable source timing.
            var composition = try await AVVideoComposition.Configuration(for: asset)
            composition.sourceTrackIDForFrameTiming = track.trackID
            composition.colorPrimaries = colors[AVVideoColorPrimariesKey] as? String
            composition.colorTransferFunction = colors[AVVideoTransferFunctionKey] as? String
            composition.colorYCbCrMatrix = colors[AVVideoYCbCrMatrixKey] as? String
            let composed = AVAssetReaderVideoCompositionOutput(videoTracks: [track], videoSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
            composed.videoComposition = AVVideoComposition(configuration: composition)
            output = composed
        } else {
            var decoderSettings: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: readFormat,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
            if !hdr && log == nil { decoderSettings[AVVideoColorPropertiesKey] = colors }
            output = AVAssetReaderTrackOutput(track: track, outputSettings: decoderSettings)
        }
        guard reader.canAdd(output) else { throw UnderBlueError.unsupported }
        let source = reader.outputProvider(for: output)
        let videoSettings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height), AVVideoColorPropertiesKey: colors,
            AVVideoCompressionPropertiesKey: VideoColorPipeline.compression(hdr: hdr, bitrate: bitrate, frameRate: metadata.frameRate)]
        guard writer.canApply(outputSettings: videoSettings, forMediaType: .video) else { throw UnderBlueError.unsupported }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false
        // Keep the source timescale. The default 1/600 s can round a last frame that starts
        // just before the end onto the end of the edit, so the file holds it but never shows it.
        let timescale = max(1, try await track.load(.naturalTimeScale))
        input.mediaTimeScale = timescale
        writer.movieTimeScale = timescale
        guard writer.canAdd(input) else { throw UnderBlueError.unsupported }
        guard let attributes = CVPixelBufferCreationAttributes(CVPixelBufferAttributes(rawAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
            kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Int](), kCVPixelBufferMetalCompatibilityKey as String: true]))
        else { throw UnderBlueError.exportFailed }
        let sink = writer.inputPixelBufferReceiver(for: input, pixelBufferAttributes: attributes)
        let end = CMTime(seconds: duration, preferredTimescale: timescale)
        reader.timeRange = CMTimeRange(start: .zero, end: end)
        let loopStartedAt = Date()
        var frames = 0
        // Keep every audio track, retaining original compressed samples and their timestamps.
        // Each audio track feeds the writer from its own task, as the receivers need: the writer interleaves the tracks,
        // so a video append can wait until audio arrives. The tasks run on this actor, so nothing leaves its isolation;
        // they take turns with the video loop at each await. A task group body could not use the writer (Swift 6 region
        // isolation). An audio task waits for `open`: a provider read before the reader starts ends the app (27 Oct 2026).
        var gates: [AsyncStream<Void>.Continuation] = []
        var audioTasks: [Task<Void, any Error>] = []
        defer { for task in audioTasks { task.cancel() } }
        for audioTrack in try await asset.loadTracks(withMediaType: .audio) {
            let format = try await audioTrack.load(.formatDescriptions).first
            let audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: format)
            guard reader.canAdd(audioOutput), writer.canAdd(audioInput) else { throw UnderBlueError.unsupported }
            let audioSource = reader.outputProvider(for: audioOutput)
            let audioSink = writer.inputReceiver(for: audioInput)
            let (ready, open) = AsyncStream<Void>.makeStream()
            gates.append(open)
            audioTasks.append(Task {
                for await _ in ready {}
                // Cancelled before the reader started (the video side failed): reading now would end the app.
                try Task.checkCancellation()
                while let sample = try await audioSource.next() {
                    try Task.checkCancellation()
                    if sample.sampleCount > 0 { try await audioSink.append(sample) }
                }
                audioSink.finish()
            })
        }
        try writer.start()
        writer.startSession(atSourceTime: .zero)
        try reader.start()
        for gate in gates { gate.finish() }
        // The particle filter returns each frame 3 frames later; `pending` holds what is ready to write.
        // Nil (HDR, Original, or kernels that failed to build) passes every frame straight through.
        let particles = removesParticles && !hdr && settings.preset != .original ? ParticleFilter(context: engine.context) : nil
        var pending: [ParticleFilter.Frame] = []
        var sourceDone = false
        var recordedRenderFallback = false
        var lastProgress = -1.0
        guard let pool = sink.pixelBufferPool else { throw UnderBlueError.exportFailed }
        while true {
            try Task.checkCancellation()
            // Out of the foreground: no new GPU or encoder work. On an iPhone 17 the same writer went on after 16 s
            // in the background; after iOS suspended the app it had failed with -11847. While a 4K export waits, the
            // free memory comes back from 2132 to about 3200 MB within 5 s; clearCaches made no difference (31 Oct 2026).
            while pause?.isPaused == true { try await Task.sleep(for: .milliseconds(50)) }
            if frames % 30 == 0, ProcessInfo.processInfo.thermalState == .critical { throw Failure(kind: .thermal, domain: "UnderBlue", code: 0) }
            guard writer.status == .writing, reader.status != .failed else { throw writer.error ?? reader.error ?? UnderBlueError.exportFailed }
            // Read until a frame is ready: up to 4 at the start, while the filter fills its look-ahead.
            // The end of the source flushes the filter.
            while pending.isEmpty && !sourceDone {
                guard let sample = try await source.next() else { sourceDone = true; pending += particles?.finish() ?? []; break }
                let time = sample.presentationTimeStamp
                guard time < end else { sourceDone = true; pending += particles?.finish() ?? []; break }
                try autoreleasepool {
                    guard var decoded = sample.withUnsafeSampleBuffer({ CMSampleBufferGetImageBuffer($0).map { CIImage(cvPixelBuffer: $0) } })
                    else { throw UnderBlueError.unreadable }
                    if let log {
                        decoded = log.decode(decoded)
                        if !hdr { decoded = engine.sdr(decoded) }
                    }
                    let source = decoded.transformed(by: toneMappedByComposition ? .identity : metadata.transform)
                    let oriented = source.transformed(by: CGAffineTransform(translationX: -source.extent.minX, y: -source.extent.minY))
                    let scaled = oriented.transformed(by: CGAffineTransform(scaleX: size.width / oriented.extent.width, y: size.height / oriented.extent.height))
                    if let particles {
                        if let ready = particles.push(scaled, at: time) { pending.append(ready) }
                    } else { pending.append(ParticleFilter.Frame(image: scaled, time: time)) }
                }
            }
            guard !pending.isEmpty else { break }
            let frame = pending.removeFirst()
            let destination = try await Self.buffer(from: pool)
            destination.withUnsafeBuffer { VideoColorPipeline.tag($0, hdr: hdr, pq: metadata.dynamicRange == .pq) }
            // One autorelease pool per frame. Without it the memory grew about 3.7 MB per frame with the
            // restoration on (flat with preset Original): the 31 s whale shark clip (931 frames) passed 3 GB on
            // an iPhone 17 and the system ended the app. With the pool the footprint stays near 230 MB.
            var renderFellBack = false
            autoreleasepool {
                let image = restoration?.stabilised(frame.image, at: frame.time.seconds) ?? frame.image
                let fallback = engine.apply(image, settings: settings, edgeGuard: false, coresWater: false)
                let corrected: CIImage
                if let moment = restoration?.moment(at: frame.time.seconds) {
                    do {
                        corrected = try restorationEngine.combined(image, moment: moment, settings: settings,
                                                                    filter: engine, preservesHDR: hdr)
                    } catch {
                        corrected = fallback
                        renderFellBack = true
                    }
                } else { corrected = fallback }
                destination.withUnsafeBuffer {
                    engine.context.render(corrected, to: $0, bounds: CGRect(origin: .zero, size: size),
                                          colorSpace: VideoColorPipeline.colorSpace(hdr: hdr, pq: metadata.dynamicRange == .pq))
                }
            }
            try await sink.append(CVReadOnlyPixelBuffer(destination), with: frame.time)
            if renderFellBack, !recordedRenderFallback, let diagnostics {
                recordedRenderFallback = true
                await diagnostics.record(.restorationFallback(.videoRender), operation: .videoRestoration)
            }
            frames += 1
            if frames.isMultiple(of: 300) { engine.context.clearCaches() }
            let fraction = min(0.99, max(0, frame.time.seconds / duration))
            if fraction - lastProgress >= 0.01 { lastProgress = fraction; await progress(fraction) }
        }
        sink.finish()
        for task in audioTasks { try await task.value }
        let frameLoopSeconds = Date().timeIntervalSince(loopStartedAt)
        try Task.checkCancellation()
        guard frames > 0, reader.status != .failed else { throw reader.error ?? UnderBlueError.unreadable }
        writer.endSession(atSourceTime: end)
        await writer.finishWriting()
        try Task.checkCancellation()
        guard writer.status == .completed else { throw writer.error ?? UnderBlueError.exportFailed }
        let result = try await OutputValidator().validate(target, source: metadata, options: options, expectedFrames: frames)
        await progress(1)
        #if DEBUG
        let elapsed = max(0.001, Date().timeIntervalSince(startedAt))
        logger.debug("frames=\(frames) seconds=\(elapsed) exportFPS=\(Double(frames) / elapsed) millisecondsPerFrame=\(elapsed * 1000 / Double(max(1, frames)))")
        #endif
        succeeded = true
        return VideoExportResult(url: target, metadata: result, frames: frames,
                                 elapsedSeconds: Date().timeIntervalSince(startedAt), frameLoopSeconds: frameLoopSeconds)
    }

    /// A buffer for the next frame. At most 6 frames wait in the encoder: past that the pool gives none, and the frame
    /// waits for one, as before the receiver API. Any other pool error fails the export.
    private static func buffer(from pool: CVMutablePixelBuffer.Pool) async throws -> CVMutablePixelBuffer {
        while true {
            do { return try pool.makeMutablePixelBuffer(.init(allocationThreshold: 6)) }
            catch let error as NSError where error.code == Int(kCVReturnWouldExceedAllocationThreshold) {
                try await Task.sleep(for: .milliseconds(2))
            }
        }
    }

    /// Free memory that Core Image must leave alone. The rest of an export (decoder, encoder, frame buffers)
    /// took about 190 MB on an iPhone 17 at 4K. With 80% of the free memory given to Core Image instead, the
    /// free memory fell to 11 MB (22 Oct 2026, docs/PerformanceMeasurement.md). An export renders only in the
    /// foreground (it waits in the background), so the free memory does not drop suddenly.
    static let memoryReserveMB = 512

    /// The memory that is free now: what the system still lets this app use on an iPhone, the free and
    /// reclaimable memory of the Mac.
    static func availableMemoryBytes() -> UInt64 {
        #if os(iOS)
        UInt64(os_proc_available_memory())
        #else
        SystemMemoryProbe().availableBytes()
        #endif
    }

    /// The smallest Core Image memory limit that gives the same pixels as a large limit: 768 MB at 4K,
    /// scaled by the pixel count. Measured at 4K on a Mac and on an iPhone 17: 768 MB and above gave
    /// identical frames; 640 MB and below changed about 0.016% of the bytes by up to 2 levels
    /// (22 Oct 2026, docs/PerformanceMeasurement.md). The speed also drops below it.
    /// The export never uses a smaller limit, so the picture does not depend on how much memory is free.
    static func minimumLimitMB(for size: CGSize) -> Int {
        Int((size.width * size.height * 768 / (3840 * 2160)).rounded(.up))
    }

    /// The Core Image memory limit for an output size: 130 bytes per pixel (4K gets about 1 GiB, where the
    /// speed stops rising). On an iPhone it is also at most the free memory minus `memoryReserveMB`, but never
    /// below `minimumLimitMB`: when the free memory is too small for that, `memoryShortage` stops the start
    /// before this runs. On a Mac nothing ends the app for lack of memory, and a limit that followed the free
    /// memory would change the pixels from one video of a batch to the next, so the limit stays fixed.
    /// Nil keeps the system default (256 MB), which is enough up to 1080p.
    /// Measured on a Mac at 720p, 1080p and 4K, and on an iPhone 17 at 4K (docs/PerformanceMeasurement.md).
    static func memoryLimitMB(for size: CGSize, availableBytes: UInt64 = VideoExporter.availableMemoryBytes()) -> Int? {
        let wanted = wantedLimitMB(for: size)
        guard wanted > 300 else { return nil }
        #if os(iOS)
        let allowed = Int(availableBytes / 1_048_576) - memoryReserveMB
        return max(min(wanted, allowed), minimumLimitMB(for: size))
        #else
        return wanted
        #endif
    }

    /// Free memory that a video export of this output size needs before it starts. 4K was measured on an
    /// iPhone 17: it finished with 1236 MB free and the app was ended with about 980 MB free (22 Oct 2026,
    /// docs/PerformanceMeasurement.md). Other sizes scale with the pixel count; they are estimates, not measured.
    /// When the export sets a limit, it is never less than the smallest limit plus the reserve, so a started
    /// export always gets a full limit. Small outputs use the system default and have no such floor.
    static func requiredAvailableMB(for size: CGSize) -> Int {
        let estimate = 300 + Int((size.width * size.height * 1000 / (3840 * 2160)).rounded(.up))
        guard coreImageLimitApplies(to: size) else { return estimate }
        return max(estimate, minimumLimitMB(for: size) + memoryReserveMB)
    }

    /// Outputs above this size need a limit set; below it the system default is enough.
    private static func coreImageLimitApplies(to size: CGSize) -> Bool {
        wantedLimitMB(for: size) > 300
    }

    private static func wantedLimitMB(for size: CGSize) -> Int {
        Int((size.width * size.height * 130 / 1_048_576).rounded(.up))
    }

    struct MemoryShortage: Equatable, Sendable {
        let availableMB: Int
        let neededMB: Int
    }

    /// Nil when enough memory is free to start. Otherwise the free and the needed amount, for the
    /// "close other apps" message.
    static func memoryShortage(outputSize: CGSize, availableMB: Int = Int(VideoExporter.availableMemoryBytes() / 1_048_576)) -> MemoryShortage? {
        let needed = requiredAvailableMB(for: outputSize)
        return availableMB < needed ? MemoryShortage(availableMB: availableMB, neededMB: needed) : nil
    }

    /// Exports a short probe with the real pipeline and scales its frame-loop time to the full length.
    func estimateSeconds(url: URL, metadata: VideoMetadata, settings: FilterSettings, options: ExportOptions,
                         restorationAnalysis: VideoRestorationAnalysis?) async throws -> Double {
        let length = min(metadata.duration, options.durationLimit ?? metadata.duration)
        var probe = options
        probe.durationLimit = min(1, length)
        let result = try await export(url: url, metadata: metadata, settings: settings, options: probe,
                                      restorationAnalysis: restorationAnalysis) { _ in }
        TemporaryFiles.remove(result.url)
        let setup = max(0, result.elapsedSeconds - result.frameLoopSeconds)
        return setup + result.frameLoopSeconds * length / min(1, length)
    }
}
