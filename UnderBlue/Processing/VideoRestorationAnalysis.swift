import AVFoundation
import CoreImage
import os

/// One stretch of video that shows the same scene. Every frame from `start` to `end` (the scene's
/// first and last keyframe) gets the same water analysis and scene-level plan, so the look holds
/// still while the scene does.
struct VideoScene: Sendable, Equatable {
    let start: Double
    let end: Double
    let analysis: WaterAnalysis
    let plan: RestorationPlan
    /// Keyframes the scene was measured on. Zero means unknown; such a scene always holds its values.
    var keyframes: Int = 0
    /// One of the scene's keyframes, small, with its own depth map. The object colour step for video makes its
    /// values from it at render time (RestorationEngine.videoObjectColour). Nil: no such step for this scene.
    var objectKeyframe: ObjectKeyframe? = nil

    func limiting(maximumOutput: Float) -> VideoScene {
        VideoScene(start: start, end: end, analysis: analysis, plan: plan.limiting(maximumOutput: maximumOutput),
                   keyframes: keyframes, objectKeyframe: objectKeyframe)
    }
}

/// A keyframe kept for the object colour step: the SDR source at most `maximumDimension` px and its depth map
/// at most `depthDimension` px. The step needs only the means of the far pixels, so small is enough.
struct ObjectKeyframe: Sendable, Equatable {
    let image: CGImage
    let depth: NormalizedDepthMap
    static let maximumDimension: CGFloat = 320
    static let depthDimension = 160

    static func make(image: CIImage, depth: DepthEstimate, context: CIContext) -> ObjectKeyframe? {
        guard !image.extent.isEmpty, let map = try? depth.resampled(maxDimension: depthDimension).map else { return nil }
        // Whole pixels on both sides (FilterEngine.downscaled): a partial edge row would enter the far-pixel means.
        let small = FilterEngine.downscaled(image, maxPixel: maximumDimension)
        guard let cg = context.createCGImage(small, from: small.extent, format: .RGBA8,
                                             colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else { return nil }
        return ObjectKeyframe(image: cg, depth: map)
    }
}

/// The values for one frame: scene `from`, moving to scene `to` by `amount` (0 is only `from`).
struct VideoSceneMoment: Sendable, Equatable {
    let from: VideoScene
    let to: VideoScene
    let amount: Float

    /// The two scene plans mixed. Scene plans carry one constant depth, so mixing the depth is safe.
    func plan() throws -> RestorationPlan {
        if amount <= 0 { return from.plan }
        if amount >= 1 { return to.plan }
        return try from.plan.mixed(with: to.plan, amount: amount)
    }

    /// The correction values for the user's current settings. Each scene gets its own make() result,
    /// then the results mix. So every value moves on a straight line between the two scenes,
    /// whatever make() does inside.
    /// The light-source decision (WaterAnalysis.lightShare) is the whole clip's, from `settings`
    /// (the clip's mean analysis), so every scene takes the same direction and none can switch.
    func corrections(settings: FilterSettings, engine: RestorationEngine) -> (current: ColorCorrection, restored: ColorCorrection) {
        var first = settings
        first.analysis = from.analysis
        first.analysis.lightShare = settings.analysis.lightShare
        let a = Self.keepingBlackOffsetNegative(engine.corrections(settings: first, plan: from.plan))
        guard amount > 0 else { return a }
        var second = settings
        second.analysis = to.analysis
        second.analysis.lightShare = settings.analysis.lightShare
        let b = Self.keepingBlackOffsetNegative(engine.corrections(settings: second, plan: to.plan))
        guard amount < 1 else { return b }
        return (a.current.mixed(with: b.current, amount: amount), a.restored.mixed(with: b.restored, amount: amount))
    }

    /// The black offset (brightness + (1 - contrast) / 2) never turns positive in a video scene.
    /// A dark scene's exposure term can push it just above zero. Then UnderBlueBlackOffset stops
    /// using its shadow toe and adds the offset to every pixel. The darkest pixels lift and the
    /// scene turns hazy, while its neighbours are fine (20 Oct 2026: 8 to 10 s of a 13 s clip,
    /// saturation 0.62 to 0.43). Photos keep the old values, so only a scene with a positive
    /// offset renders differently from the photo path.
    /// Also tried and removed: keeping each scene's brightness within 0.01 of the clip's. It cut the
    /// jump at scene changes (9.4 to 5.7 L*), but a bright blue scene lost its veil offset and got a
    /// pale rim around dark subjects (2025-05-03 22.12.02, 5 s: ring minus far water -2.6 to -0.9 L*).
    static func keepingBlackOffsetNegative(
        _ values: (current: ColorCorrection, restored: ColorCorrection)
    ) -> (current: ColorCorrection, restored: ColorCorrection) {
        func capped(_ value: ColorCorrection) -> ColorCorrection {
            var v = value
            v.brightness = min(v.brightness, (v.contrast - 1) * 0.5)
            return v
        }
        return (capped(values.current), capped(values.restored))
    }

    func limiting(maximumOutput: Float) -> VideoSceneMoment {
        VideoSceneMoment(from: from.limiting(maximumOutput: maximumOutput),
                         to: to.limiting(maximumOutput: maximumOutput), amount: amount)
    }
}

struct InitialRestorationEnvironment: Sendable, Equatable {
    let backscatterInfinity: SIMD3<Float>
    let betaDirect: SIMD3<Float>
    let betaBackscatter: SIMD3<Float>
    let channelRecoverability: SIMD3<Float>
    let confidence: Float
}

struct VideoRestorationAnalysis: Sendable {
    /// The whole clip's mean analysis. The editor keeps it in its settings; rendering uses the scenes.
    let legacyAnalysis: WaterAnalysis
    let representativeFrame: CGImage
    let representativeTime: Double
    /// In time order. Empty when no keyframe gave a physical plan; video then uses the legacy correction.
    let scenes: [VideoScene]
    let initialEnvironment: InitialRestorationEnvironment?
    let deviceProfile: DeviceCapabilityProfile
    let sourceProfile: VideoSourceProfile
    let previewPolicy: ProcessingPolicy
    let exportPolicy: ProcessingPolicy
    /// The camera's short colour pulses, taken out of every frame before the correction. Nil keeps the frames.
    var colourTrack: VideoColourTrack? = nil

    /// The source frame at `time` as the correction should see it. Preview and export both use this.
    func stabilised(_ image: CIImage, at time: Double) -> CIImage {
        colourTrack?.stabilised(image, at: time) ?? image
    }

    /// The longest cross-fade between two scenes, in seconds. The change happens somewhere between
    /// two keyframes, so the fade is centred on the middle of that gap. It may be longer than the gap:
    /// the fade then reaches into both scenes, but never into the next fade (half of the distance to
    /// the neighbouring fade centre at most). 1 s made scene jumps up to 9 L* on a 42 s clip; 3 s took
    /// the same clip to 6.7 L* and cut the rms jump by 11 to 25% on three test clips, with no change
    /// in the scene split or the colour (20 Oct 2026, Mac simulation, no cost in analysis time).
    static let sceneFade: Double = 3

    /// A scene measured on fewer keyframes is a passing state, not a scene to hold. Its values come
    /// from one or two keyframes, which jitter. While the camera turned toward the surface and back
    /// (video2, 14 to 18 s), such scenes switched the values against the light: the output got darker
    /// while the source got brighter. So a short scene between two held scenes is skipped, and its
    /// neighbours fade across the whole gap. A short scene at the start or end of the clip is the only
    /// measurement of that stretch, so it stays (skipping the last one turned the challenge clip's last
    /// second grey: 0.1% to 32% of the frame).
    static let heldSceneKeyframes = 3

    /// The scene values for one frame. Preview and export both use this, so they match.
    func moment(at time: Double) -> VideoSceneMoment? {
        let held = scenes.indices.filter { scenes[$0].keyframes == 0 || scenes[$0].keyframes >= Self.heldSceneKeyframes }
        let used = scenes.indices.filter { index in
            guard let first = held.first, let last = held.last else { return true }
            return held.contains(index) || index < first || index > last
        }
        guard let firstIndex = used.first else { return nil }
        let middles = zip(used, used.dropFirst()).map { (scenes[$0].end + scenes[$1].start) / 2 }
        /// Half the length of fade `t`, between used[t] and used[t + 1].
        func halfWidth(_ t: Int) -> Double {
            let gap = scenes[used[t + 1]].start - scenes[used[t]].end
            // A skipped short scene: the neighbours fade across the whole gap.
            if used[t + 1] > used[t] + 1 { return gap / 2 }
            var room = Double.infinity
            if t > 0 { room = min(room, middles[t] - middles[t - 1]) }
            if t + 1 < middles.count { room = min(room, middles[t + 1] - middles[t]) }
            return max(min(Self.sceneFade, gap) / 2, min(Self.sceneFade / 2, room / 2))
        }
        var current = scenes[firstIndex]
        for (t, nextIndex) in used.dropFirst().enumerated() {
            let next = scenes[nextIndex]
            let middle = middles[t], half = halfWidth(t)
            if time < middle + half {
                guard half > 0, time > middle - half else { return VideoSceneMoment(from: current, to: current, amount: 0) }
                // Smoothstep: the fade starts and ends without a jolt.
                let x = Float((time - (middle - half)) / (2 * half))
                return VideoSceneMoment(from: current, to: next, amount: x * x * (3 - 2 * x))
            }
            current = next
        }
        return VideoSceneMoment(from: current, to: current, amount: 0)
    }
}

/// Splits keyframes into scenes. A new scene starts where the mean colour moves more than
/// `threshold` (OKLab distance) from the running scene's mean, and the next keyframe is that far
/// too. So one odd keyframe never starts a scene.
/// 0.04 is twice the largest drift of a steady 20 s stretch of a real dive clip (28 Sep 2026). On
/// that clip it splits where the camera turns to the sunlit surface and where it turns to deep water.
enum VideoSceneSplitter {
    static let threshold: Float = 0.04

    /// The index of each scene's first keyframe, in order. Starts with 0 when there is a keyframe.
    static func sceneStarts(_ samples: [WaterAnalysis], threshold: Float = threshold) -> [Int] {
        guard !samples.isEmpty else { return [] }
        let colors = samples.map { sample -> SIMD3<Float> in
            let c = sample.meanColor
            return ColorCorrection.oklab(c.x.isFinite && c.y.isFinite && c.z.isFinite ? c : .zero)
        }
        var starts = [0], sum = colors[0], count: Float = 1
        for index in colors.indices.dropFirst() {
            let center = sum / count
            func far(_ i: Int) -> Bool {
                guard i < colors.count else { return false }
                let d = colors[i] - center
                return (d * d).sum().squareRoot() > threshold
            }
            if far(index) && far(index + 1) {
                starts.append(index)
                sum = colors[index]; count = 1
            } else {
                sum += colors[index]; count += 1
            }
        }
        return starts
    }
}
