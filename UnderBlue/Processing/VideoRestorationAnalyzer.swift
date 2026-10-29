import AVFoundation
import CoreImage
import os

actor VideoRestorationAnalyzer {
    /// Keyframe spacing in seconds on ordinary clips. Short clips still get `minimumKeyframes` and long
    /// clips at most `maximumKeyframes`, so a one-hour clip takes a keyframe every 30 s.
    static let keyframeSpacing: Double = 1
    static let minimumKeyframes = 10
    static let maximumKeyframes = 120
    /// Depth and the water fit are the slow part. Each scene fits at most this many of its keyframes,
    /// evenly spread, so a steady clip fits as many as the old 10-sample analysis did.
    static let maximumFitsPerScene = 10

    /// Keyframe times from the first frame to 0.1 s before the end, evenly spaced.
    static func keyframeTimes(duration: Double) -> [Double] {
        let last = max(0, duration - 0.1)
        let count = min(maximumKeyframes, max(minimumKeyframes, Int(last / keyframeSpacing) + 1))
        guard last > 0, count > 1 else { return [0] }
        return (0..<count).map { last * Double($0) / Double(count - 1) }
    }

    /// At most `count` indices of `range`, evenly spread, the first and the last included.
    static func spread(_ range: Range<Int>, count: Int) -> [Int] {
        guard count > 1, range.count > count else { return Array(range.prefix(max(1, count))) }
        return (0..<count).map { range.lowerBound + Int((Double($0) * Double(range.count - 1) / Double(count - 1)).rounded()) }
    }

    private let engine = FilterEngine()
    private let waterEstimator = WaterModelEstimator()
    private let restorationEngine = RestorationEngine()
    private let profiler: DeviceCapabilityProfiler
    private let diagnostics: DiagnosticRecorder?
    private let signposter = OSSignposter(subsystem: "com.underblue.app", category: "video-analysis")
    #if DEBUG
    private let logger = Logger(subsystem: "com.underblue.app", category: "video-analysis")
    #endif

    init(profiler: DeviceCapabilityProfiler = DeviceCapabilityProfiler(),
         diagnostics: DiagnosticRecorder? = nil) {
        self.profiler = profiler
        self.diagnostics = diagnostics
    }

    func analyze(url: URL, metadata: VideoMetadata) async throws -> VideoRestorationAnalysis {
        let interval = signposter.beginInterval("Keyframe analysis")
        defer { signposter.endInterval("Keyframe analysis", interval) }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 960)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.03, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.03, preferredTimescale: 600)
        // An Apple Log frame comes out of the generator as the log signal, so it is decoded first.
        let log = metadata.appleLog
        let engine = engine
        @Sendable func mapped(_ image: CIImage) -> CIImage { engine.sdr(log?.decode(image) ?? image) }
        let videoDuration = metadata.videoDuration
        // Every frame's colour balance, so the keyframes and the rendered frames lose the camera's short
        // colour pulses alike (VideoColourTrack). A clip it cannot read keeps its frames as they are.
        let colourTrack: VideoColourTrack?
        // An SDR clip is measured on the CPU (VideoColourTrack.measure).
        var measured: (@Sendable (CIImage) -> CIImage)?
        if log != nil || metadata.isHDR { measured = mapped }
        do { colourTrack = try await VideoColourTrack.measure(url: url, duration: videoDuration, context: engine.context, frame: measured) }
        catch is CancellationError { throw CancellationError() } catch { colourTrack = nil }
        func frame(_ cg: CGImage, at time: CMTime) -> CIImage {
            let image = mapped(CIImage(cgImage: cg))
            return colourTrack?.stabilised(image, at: time.seconds) ?? image
        }

        // One frame that cannot be read must not stop the whole analysis (code 6, video3, 1 Oct 2026):
        // a failed keyframe is skipped, and only a clip with no readable keyframe fails.
        // Keyframes stay inside the video track: a longer audio track ran them past the last frame.
        let keyframes = Self.keyframeTimes(duration: videoDuration)
        var times: [Double] = [], actualTimes: [CMTime] = [], samples: [WaterAnalysis] = [], firstFrame: (CGImage, CMTime)?
        for time in keyframes {
            try Task.checkCancellation()
            let read: (image: CGImage, actualTime: CMTime)
            do { read = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)) }
            catch is CancellationError { throw CancellationError() } catch { continue }
            if firstFrame == nil { firstFrame = (read.image, read.actualTime) }
            times.append(time)
            actualTimes.append(read.actualTime)
            samples.append(engine.analyze(frame(read.image, at: read.actualTime)))
        }
        guard let firstFrame else { throw UnderBlueError.unreadable }
        var representativeTime = max(0, videoDuration * 0.5)
        let representative: CGImage
        let representativeImage: CIImage
        do {
            let read = try await generator.image(at: CMTime(seconds: representativeTime, preferredTimescale: 600))
            representative = read.image
            representativeImage = frame(read.image, at: read.actualTime)
        } catch is CancellationError { throw CancellationError() } catch {
            representative = firstFrame.0; representativeTime = times[0]
            representativeImage = frame(firstFrame.0, at: firstFrame.1)
        }
        let device = await profiler.profile(representativeImage: representativeImage)
        let source = VideoSourceProfile.make(url: url, metadata: metadata)
        let runtime = RuntimeSystemState.current
        let builder = ProcessingPolicyBuilder()
        let previewPolicy = builder.make(device: device, source: source, runtime: runtime, purpose: .preview)
        let exportPolicy = builder.make(device: device, source: source, runtime: runtime, purpose: .export)
        let depthEstimator = DepthEstimator(computeUnits: device.preferredComputePolicy.coreML)

        // Video rule: a keyframe about every second. Keyframes that show the same scene form one scene
        // (VideoSceneSplitter). A scene averages its keyframes, drops odd ones, and its values hold for
        // the whole scene. Between two scenes the values cross-fade (VideoRestorationAnalysis.moment).
        let starts = VideoSceneSplitter.sceneStarts(samples)
        let ranges = zip(starts, starts.dropFirst() + [samples.count]).map { $0..<$1 }

        var plans: [Int: RestorationPlan] = [:]
        var objectKeyframes: [Int: ObjectKeyframe] = [:]
        var restorationFailures = 0
        for range in ranges {
            for index in Self.spread(range, count: Self.maximumFitsPerScene) {
                try Task.checkCancellation()
                let cg: CGImage
                do { cg = try await generator.image(at: CMTime(seconds: times[index], preferredTimescale: 600)).image }
                catch is CancellationError { throw CancellationError() } catch { restorationFailures += 1; continue }
                let image = frame(cg, at: actualTimes[index])
                do {
                    let depth = try await depthEstimator.monocularDepth(for: image)
                        .resampled(maxDimension: previewPolicy.depthMapMaxDimension)
                    plans[index] = try waterEstimator.estimate(image: image, depth: depth, legacy: samples[index],
                                                               context: engine.context)
                    objectKeyframes[index] = ObjectKeyframe.make(image: image, depth: depth, context: engine.context)
                } catch is CancellationError { throw CancellationError() }
                catch {
                    restorationFailures += 1
                    #if DEBUG
                    logger.debug("keyframe=\(times[index]) physical-restoration unavailable; retaining UnderBlue fallback")
                    #endif
                }
            }
        }
        if restorationFailures > 0, let diagnostics {
            await diagnostics.record(.restorationFallback(.videoInitialAnalysis),
                                     operation: .videoRestoration,
                                     occurrences: restorationFailures)
        }

        // sceneLevel() shrinks the constant depth map to 2x2, so each frame uploads 16 bytes, not a full map.
        // Only kept keyframes enter a plan: rejected ones must not re-enter the physical correction.
        func scenePlan(_ kept: [Int]) -> RestorationPlan? {
            let chosen = kept.compactMap { plans[$0] }
            return try? RestorationPlan.sceneAverage(chosen, keeping: Array(chosen.indices)).sceneLevel()
        }
        let clipKept = WaterAnalysis.sceneInliers(samples)
        var sceneValues: [(range: Range<Int>, analysis: WaterAnalysis, plan: RestorationPlan?, keyframe: ObjectKeyframe?,
                           measured: [ObjectKeyframe])] = []
        for range in ranges {
            let members = Array(range)
            let kept = WaterAnalysis.sceneInliers(members.map { samples[$0] }).map { members[$0] }
            // The middle kept keyframe that has a fit (and so a depth map).
            let withKeyframe = kept.filter { plans[$0] != nil && objectKeyframes[$0] != nil }
            let keyframe = withKeyframe.isEmpty ? nil : objectKeyframes[withKeyframe[withKeyframe.count / 2]]
            sceneValues.append((range, WaterAnalysis.sceneMean(samples, keeping: kept), scenePlan(kept), keyframe,
                                withKeyframe.compactMap { objectKeyframes[$0] }))
        }
        // A scene whose fits all failed borrows the whole clip's plan. If every fit failed, no scene
        // has a plan and video keeps only the legacy correction.
        var scenes: [VideoScene] = []
        // Each scene's residual cast is measured on its kept keyframes with the scene plan, as frames render it. A
        // scene without one keeps the full cast gains.
        if let fallback = scenePlan(clipKept) ?? sceneValues.lazy.compactMap({ $0.plan }).first {
            scenes = sceneValues.map { scene in
                let plan = scene.plan ?? fallback
                return VideoScene(start: times[scene.range.lowerBound], end: times[scene.range.upperBound - 1],
                                  analysis: scene.analysis,
                                  plan: restorationEngine.measuringResidualCast(plan, images: scene.measured.map { CIImage(cgImage: $0.image) },
                                                                                filter: engine, video: true),
                                  keyframes: scene.range.count, objectKeyframe: scene.keyframe)
            }
        }
        let environment = aggregate(clipKept.compactMap { plans[$0] })
        #if DEBUG
        logger.debug("keyframes=\(times.count) scenes=\(starts.map { times[$0] }) fits=\(plans.count) failures=\(restorationFailures) workload=\(source.workload.rawValue, privacy: .public) previewDepth=\(previewPolicy.depthMapMaxDimension)")
        #endif
        Task.detached(priority: .utility) {
            await self.profiler.completeBenchmarkIfNeeded(representativeImage: representativeImage)
        }
        return VideoRestorationAnalysis(legacyAnalysis: .sceneMean(samples, keeping: clipKept),
                                        representativeFrame: representative, representativeTime: representativeTime,
                                        scenes: scenes, initialEnvironment: environment, deviceProfile: device,
                                        sourceProfile: source, previewPolicy: previewPolicy, exportPolicy: exportPolicy,
                                        colourTrack: colourTrack)
    }

    private func aggregate(_ plans: [RestorationPlan]) -> InitialRestorationEnvironment? {
        let accepted = plans.filter { $0.confidence >= 0.08 }
        guard !accepted.isEmpty else { return nil }
        func scalar(_ key: (RestorationPlan) -> Float) -> Float {
            weightedMedian(accepted.map { (key($0), max(0.001, $0.confidence)) })
        }
        func vector(_ key: (RestorationPlan) -> SIMD3<Float>) -> SIMD3<Float> {
            SIMD3(weightedMedian(accepted.map { (key($0).x, max(0.001, $0.confidence)) }),
                  weightedMedian(accepted.map { (key($0).y, max(0.001, $0.confidence)) }),
                  weightedMedian(accepted.map { (key($0).z, max(0.001, $0.confidence)) }))
        }
        return InitialRestorationEnvironment(backscatterInfinity: vector(\.backscatterInfinity),
                                             betaDirect: vector(\.betaDirect),
                                             betaBackscatter: vector(\.betaBackscatter),
                                             channelRecoverability: vector(\.channelRecoverability),
                                             confidence: scalar(\.confidence))
    }

    private func weightedMedian(_ input: [(Float, Float)]) -> Float {
        let values = input.filter { $0.0.isFinite && $0.1.isFinite && $0.1 > 0 }.sorted { $0.0 < $1.0 }
        guard !values.isEmpty else { return 0 }
        let half = values.reduce(Float(0)) { $0 + $1.1 } / 2
        var accumulated: Float = 0
        for value in values {
            accumulated += value.1
            if accumulated >= half { return value.0 }
        }
        return values.last!.0
    }
}
