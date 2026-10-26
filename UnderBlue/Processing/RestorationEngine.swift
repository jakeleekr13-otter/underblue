import CoreImage
import os
import simd
import CoreImage.CIFilterBuiltins


final class RestorationEngine: Sendable {
    private let kernel: CIColorKernel?
    private let detailKernel: CIColorKernel?
    private let depthBlendKernel: CIColorKernel?
    private let subjectWeightKernel: CIColorKernel?
    private let subjectFreeLightKernel: CIColorKernel?
    private let liftKernel: CIColorKernel?
    private let signalKernel: CIColorKernel?
    // Not private: the object colour step lives in RestorationEngine+ObjectColour.swift.
    let objectColourKernel: CIColorKernel?
    let objectColourVideoKernel: CIColorKernel?
    /// Video object colour values per scene and settings (videoObjectColourValues). Few entries: one per scene the
    /// preview or export is on, and the settings change only when a slider moves.
    let videoObjectCache = OSAllocatedUnfairLock(initialState: [VideoObjectCacheEntry]())
    /// depthTrust per video scene (its keyframe), keyed like videoObjectCache.
    let sceneTrustCache = OSAllocatedUnfairLock(initialState: [(key: VideoObjectCacheEntry.Key, trust: Float)]())
    /// Depth (normalized) from which a pixel takes the full restored result. See combined().
    static let nearDepth: Float = 0.25

    init() {
        kernel = MetalKernels.color("UnderBlueRestoration")
        detailKernel = MetalKernels.color("UnderBlueRestoredDetail")
        depthBlendKernel = MetalKernels.color("UnderBlueDepthBlend")
        subjectWeightKernel = MetalKernels.color("UnderBlueSubjectWeight")
        subjectFreeLightKernel = MetalKernels.color("UnderBlueSubjectFreeLight")
        liftKernel = MetalKernels.color("UnderBlueLiftToWide")
        signalKernel = MetalKernels.color("UnderBlueContrastTransmission")
        objectColourKernel = MetalKernels.color("UnderBlueObjectColour")
        objectColourVideoKernel = MetalKernels.color("UnderBlueObjectColourVideo")
    }

    /// The blur (share of the short side, at least 1.5 px) that splits the source into the part
    /// the restoration acts on and the fine detail. See restore(_:plan:).
    static let detailSplitRadius: Float = 0.0015
    /// The wide light that dark pixels are lifted to, in broad-light radii (video, see restore).
    static let liftWideScale: Float = 3

    /// The restoration removes the veil and divides by the transmission. On fine detail that is
    /// mostly noise: the veil takes signal, not noise, and the division then scales both. Far water
    /// got about twice the noise per signal (IMG_7260, 28 Sep 2026). So the restoration acts on a
    /// slightly blurred source, and the source's fine detail comes back at the pixel's own
    /// restoration ratio. The mean colour is the same; detail keeps its share of the signal.
    func restore(_ image: CIImage, plan: RestorationPlan, liftDark: Bool = false) throws -> CIImage {
        guard let kernel else { throw RestorationError.kernelUnavailable }
        let depth = try depthImage(plan.depth, matching: image.extent)
        let limits = plan.limits
        let short = Float(min(image.extent.width, image.extent.height))
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = image.clampedToExtent()
        blur.radius = max(1.5, Self.detailSplitRadius * (short.isFinite ? short : 0))
        let low = detailKernel == nil ? image : (blur.outputImage ?? image).cropped(to: image.extent)
        // The broad light around each pixel, for the local veil (RestorationMath.localVeil).
        let broadRadius = max(4, RestorationMath.localVeilRadius * (short.isFinite ? short : 0))
        func broadBlur(_ input: CIImage) -> CIImage {
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = input.clampedToExtent()
            blur.radius = broadRadius
            return (blur.outputImage ?? input).cropped(to: image.extent)
        }
        var broad = broadBlur(image)
        // Video has no photo mask. With liftDark, a pixel darker than the wide light around it (a dark
        // fish or shark) is lifted to that light before the broad blur, twice, so the dark pixels weigh
        // less in their own wide light. Water next to a dark subject then gets the veil of open water.
        // Without it that water kept more veil and showed a bright halo (instagram-media, 22 Oct 2026).
        if liftDark, plan.subjectMask == nil, let liftKernel {
            var lifted = low
            for _ in 0..<2 {
                let wideBlur = CIFilter.gaussianBlur()
                wideBlur.inputImage = lifted.clampedToExtent()
                wideBlur.radius = broadRadius * Self.liftWideScale
                let wide = (wideBlur.outputImage ?? lifted).cropped(to: image.extent)
                lifted = liftKernel.apply(extent: image.extent, arguments: [low, wide])?.cropped(to: image.extent) ?? lifted
            }
            broad = broadBlur(lifted)
        }
        // Outside the photo's subjects the broad light leaves them out: a blur of the source
        // weighted by (1 - mask), divided by the blur of the weight. See SubjectMask.
        if let subjects = plan.subjectMask, let subjectWeightKernel, let subjectFreeLightKernel {
            let mask = subjects.image(matching: image.extent)
            if let weighted = subjectWeightKernel.apply(extent: image.extent, arguments: [image, mask, 0]),
               let weight = subjectWeightKernel.apply(extent: image.extent, arguments: [image, mask, 1]),
               let free = subjectFreeLightKernel.apply(extent: image.extent, arguments: [
                   broadBlur(weighted), broadBlur(weight), broad, mask]) {
                broad = free.cropped(to: image.extent)
            }
        }
        let restoredLow = kernel.apply(extent: image.extent, arguments: [
            low, depth, broad,
            vector(plan.backscatterInfinity), vector(plan.betaDirect), vector(plan.betaBackscatter),
            CIVector(x: CGFloat(limits.transmissionFloor), y: CGFloat(limits.highlightStart),
                     z: CGFloat(limits.highlightEnd), w: CGFloat(limits.maximumOutput)),
            vector(limits.maximumGain), vector(plan.channelRecoverability),
            CIVector(x: CGFloat(plan.veilLevel), y: CGFloat(RestorationMath.localVeilRange.lowerBound),
                     z: CGFloat(RestorationMath.localVeilRange.upperBound), w: liftDark ? 1 : 0)
        ])
        guard let restoredLow else { throw RestorationError.kernelUnavailable }
        guard let detailKernel, low !== image else { return restoredLow.cropped(to: image.extent) }
        let output = detailKernel.apply(extent: image.extent, arguments: [image, low, restoredLow, vector(limits.maximumGain)])
        return (output ?? restoredLow).cropped(to: image.extent)
    }

    private func depthImage(_ map: NormalizedDepthMap, matching extent: CGRect) throws -> CIImage {
        let data = map.values.withUnsafeBytes { Data($0) }
        let depth = CIImage(bitmapData: data, bytesPerRow: map.width * MemoryLayout<Float>.size,
                            size: CGSize(width: map.width, height: map.height), format: .Rf, colorSpace: nil)
        // Clamped, then cropped: the scaled map is sampled between pixels, so at the border it read
        // the empty space outside the map. How much depended on the region the later filters asked
        // for, so a blur anywhere after the restoration changed the restored edge rows. The 2x2 test
        // plan's bottom rows lost 5% (VideoRestorationTests edge test 0.948 with the water calm, 8 Oct 2026).
        let scaled = depth.clampedToExtent().transformed(by: CGAffineTransform(scaleX: extent.width / CGFloat(map.width),
                                                                               y: extent.height / CGFloat(map.height)))
        return scaled.transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY)).cropped(to: extent)
    }

    private func vector(_ value: SIMD3<Float>) -> CIVector {
        CIVector(x: CGFloat(value.x), y: CGFloat(value.y), z: CGFloat(value.z), w: 0)
    }

    func combined(_ image: CIImage, plan: RestorationPlan, settings: FilterSettings,
                  filter: FilterEngine, subjectLift: SubjectLift? = nil) throws -> CIImage {
        try combined(image, plan: plan, values: corrections(settings: settings, plan: plan),
                     settings: settings, filter: filter, subjectLift: subjectLift)
    }

    /// combined() with correction values the caller already made. Video mixes two scenes' values here.
    /// `depthTrust`: how far depth shows where the water is (depthTrust(_:depth:correction:filter:)). Nil measures it on
    /// the plan's own depth, as photos do. A constant-depth plan (video) cannot show it: the caller passes the scene's.
    /// `measuring` returns the frame before the subject lift and the object colour step (photos measure that frame).
    func combined(_ image: CIImage, plan: RestorationPlan,
                  values: (current: ColorCorrection, restored: ColorCorrection),
                  settings: FilterSettings, filter: FilterEngine, video: Bool = false,
                  subjectLift: SubjectLift? = nil, depthTrust knownTrust: Float? = nil, measuring: Bool = false) throws -> CIImage {
        let correctionValues = values
        let amount = min(1, max(0, settings.appliedIntensity))
        guard settings.preset != .original else { return image }
        guard amount > 0 else {
            // Intensity 0 leaves the photo as it is. The subject strength is its own slider (Jake, 25 Oct 2026,
            // docs/ManualSubject.md), so the picked subjects still get their lift, on the untouched photo.
            guard let subjectLift else { return image }
            let share = subjectLift.tier2 > 0 || subjectLift.tier3 > 0 ? filter.waterShare(image, correction: values.current) : nil
            return lifted(image, subjectLift, filter, share, contrastTransmission(image, plan: plan))
        }
        // Both paths calm the water the source shows. On the restored image the water test read 0.65
        // in far water and below 0.2 near a subject, which left a noisy band (IMG_7260, 8 Oct 2026).
        let calm = filter.waterCalmWeight(image, correction: values.current)
        // Tier two of the lift reads the raw water share, not the spread calm weight.
        let share = (subjectLift?.tier2 ?? 0) > 0 || (subjectLift?.tier3 ?? 0) > 0
            ? filter.waterShare(image, correction: values.current) : nil
        // The tiers and the sharpening follow how much of an object's contrast survives the water.
        let liftSignal = subjectLift == nil ? nil : contrastTransmission(image, plan: plan)
        let current = filter.apply(image, correction: values.current, intensity: amount, calmWeight: calm, violetCalm: false, openWaterRed: video,
                                   edgeGuard: !video, coresWater: !video)
        let physicallyRestored = try restore(image, plan: plan, liftDark: video)
        // Subject light removal on the restored path only where depth can be trusted. In open water, removing the
        // backscatter steepens the glow around the sun; the glow then reads as "not water", the removal takes its blue,
        // and the class flips at one radius: a pink ring (hammerhead clips, 26 Oct 2026).
        // A constant-depth plan cannot tell; it keeps the removal, as before.
        let constantDepth = (plan.depth.values.max() ?? 0) - (plan.depth.values.min() ?? 0) <= 0.05
        let trust = knownTrust ?? (constantDepth ? 1 : depthTrust(image, plan: plan, correction: values.current, filter: filter))
        let finished = filter.finishing(physicallyRestored, correction: Self.trusting(values.restored, depthTrust: trust), reference: image, calmWeight: calm, openWaterRed: video,
                                       edgeGuard: !video, coresWater: !video)
        let depthAware = filter.blend(image, finished, amount: amount)
        // Low-confidence fits approach the exact current UnderBlue output. So do the nearest pixels
        // (depth 0 to nearDepth): the restoration leaves them almost as they are, but the restored
        // values are made for the restored water. On the sunfish's belly (depth 0) the restored
        // water tone turned the unrestored cyan green (28 Sep 2026, O3: hue 150 -> 200).
        // A constant-depth plan (video, one depth per scene) keeps one weight for the frame.
        let weight = values.restored.physicalWeight
        let values = plan.depth.values
        guard let nearest = values.min(), let farthest = values.max(), farthest - nearest > 0.05,
              let depthBlendKernel else {
            return filter.violetCalm(lifted(filter.blend(current, depthAware, amount: weight), subjectLift, filter, share, liftSignal),
                                     source: image, calmWeight: calm)
        }
        let depth = try depthImage(plan.depth, matching: image.extent)
        let mixed = depthBlendKernel.apply(extent: image.extent, arguments: [current, depthAware, depth,
            CIVector(x: CGFloat(weight), y: CGFloat(Self.nearDepth), z: 0, w: 0)])
        let blended = (mixed ?? filter.blend(current, depthAware, amount: weight)).cropped(to: image.extent)
        let unlifted = filter.violetCalm(blended, source: image, calmWeight: calm)
        if measuring { return unlifted }
        let finishedFrame = subjectLift == nil ? unlifted
            : filter.violetCalm(lifted(blended, subjectLift, filter, share, liftSignal), source: image, calmWeight: calm)
        // Photos only: video holds one depth per scene, so it never reaches this path, and the flag keeps it out too.
        guard !video else { return finishedFrame }
        // The step measures the frame before the lift. Measured after it, the lift moved the near mean, and at a subject
        // strength of 140 % the step switched on for the whole photo: the water turned warm (squid, Intensity 10 %,
        // Jake, 26 Oct 2026, docs/ManualSubject.md). With no lift the two frames are the same.
        // The step reads the frame at depth-map size. Shrinking the full frame that far made Core Image render the whole
        // pipeline at full size in one buffer: 390 MB for a 48 MP photo, above its 256 MB intermediate limit, so the
        // export failed (iPhone 17, 26 Oct 2026). So a copy of the source at twice the depth map's size goes through the
        // same pipeline, and that copy is measured.
        let measureSize = CGFloat(2 * max(plan.depth.width, plan.depth.height))
        var measured = unlifted
        if max(image.extent.width, image.extent.height) > measureSize {
            measured = try combined(FilterEngine.downscaled(image, maxPixel: measureSize), plan: plan, values: correctionValues,
                                    settings: settings, filter: filter, depthTrust: trust, measuring: true)
        }
        return objectColour(finishedFrame, measuredOn: measured, plan: plan, depth: depth, redLoss: settings.analysis.redLoss,
                            context: filter.context, depthTrust: trust)
    }


    /// The subject lift, at the one place it may run. Both of combined()'s return points go through here,
    /// so a fix cannot land on only one of them (docs/SubjectEmphasis.md).
    private func lifted(_ image: CIImage, _ lift: SubjectLift?, _ filter: FilterEngine,
                        _ waterShare: CIImage?, _ signal: CIImage?) -> CIImage {
        guard let lift else { return image }
        return filter.subjectLift(image, lift: lift, waterShare: waterShare, signal: signal)
    }

    /// How much of an object's contrast survives the water in front of it (UnderBlueContrastTransmission),
    /// from the plan's own water fit, so clear water keeps a far reef sharp and murky water does not.
    /// A share of the pixel's light was tried first and dropped: the plan's veil sits below the bright
    /// water near the surface and above a dark diver, so it read water as object and the diver as veil
    /// (E17, 23 Oct 2026). Nil without the kernel or the depth.
    func contrastTransmission(_ image: CIImage, plan: RestorationPlan) -> CIImage? {
        guard let signalKernel, let depth = try? depthImage(plan.depth, matching: image.extent) else { return nil }
        return signalKernel.apply(extent: image.extent, arguments: [depth, vector(plan.betaDirect)])?.cropped(to: image.extent)
    }

    /// The correction values combined applies: one set for the source image, one for the restored image.
    func corrections(settings: FilterSettings, plan: RestorationPlan) -> (current: ColorCorrection, restored: ColorCorrection) {
        (ColorCorrection.make(analysis: settings.analysis, preset: settings.preset, adjustments: settings.adjustments),
         ColorCorrection.make(analysis: settings.analysis, preset: settings.preset, plan: plan, adjustments: settings.adjustments))
    }
}
