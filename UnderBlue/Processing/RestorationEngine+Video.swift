import CoreImage

extension RestorationEngine {
    /// combined() for one video frame. HDR output keeps its highlight headroom (maximum output 8).
    func combined(_ image: CIImage, moment: VideoSceneMoment, settings: FilterSettings,
                  filter: FilterEngine, preservesHDR: Bool = false) throws -> CIImage {
        let moment = preservesHDR ? moment.limiting(maximumOutput: 8) : moment
        let trust = sceneTrust(moment.from, settings: settings, filter: filter, preservesHDR: preservesHDR)
        let mixedTrust = moment.amount > 0
            ? trust + (sceneTrust(moment.to, settings: settings, filter: filter, preservesHDR: preservesHDR) - trust) * moment.amount : trust
        let frame = try combined(image, plan: moment.plan(), values: moment.corrections(settings: settings, engine: self),
                                 settings: settings, filter: filter, video: true, depthTrust: mixedTrust)
        guard let values = videoObjectColourValues(moment, settings: settings, filter: filter, preservesHDR: preservesHDR) else { return frame }
        return videoObjectColour(frame, values: values)
    }

    /// How far a scene's depth shows where the water is (depthTrust), measured on its keyframe's own depth map, since
    /// the scene plan holds one constant depth. A scene without a keyframe keeps full trust (the behaviour before).
    func sceneTrust(_ scene: VideoScene, settings: FilterSettings, filter: FilterEngine, preservesHDR: Bool) -> Float {
        guard let keyframe = scene.objectKeyframe else { return 1 }
        let key = VideoObjectCacheEntry.Key(start: scene.start, end: scene.end, settings: settings, preservesHDR: preservesHDR)
        if let hit = sceneTrustCache.withLock({ $0.first { $0.key == key } }) { return hit.trust }
        let held = VideoSceneMoment(from: scene, to: scene, amount: 0)
        let trust = depthTrust(CIImage(cgImage: keyframe.image), depth: keyframe.depth,
                               correction: held.corrections(settings: settings, engine: self).current, filter: filter)
        sceneTrustCache.withLock { entries in
            entries.removeAll { $0.key == key }
            entries.append((key, trust))
            if entries.count > VideoObjectCacheEntry.capacity { entries.removeFirst(entries.count - VideoObjectCacheEntry.capacity) }
        }
        return trust
    }

    /// One scene's values with the current settings: its keyframe through the video path, then the far pixels'
    /// mean. Made from the settings in use, not the analysis', so a slider that moves the water moves the reference too.
    func videoObjectColourValues(_ scene: VideoScene, settings: FilterSettings, filter: FilterEngine,
                                 preservesHDR: Bool) -> VideoObjectColourValues? {
        guard let keyframe = scene.objectKeyframe else { return nil }
        let key = VideoObjectCacheEntry.Key(start: scene.start, end: scene.end, settings: settings, preservesHDR: preservesHDR)
        if let hit = videoObjectCache.withLock({ $0.first { $0.key == key } }) { return hit.values }
        let source = CIImage(cgImage: keyframe.image)
        let held = VideoSceneMoment(from: scene, to: scene, amount: 0)
        let values = (try? combined(source, plan: held.plan(), values: held.corrections(settings: settings, engine: self),
                                    settings: settings, filter: filter, video: true,
                                    depthTrust: sceneTrust(scene, settings: settings, filter: filter, preservesHDR: preservesHDR))).flatMap {
            Self.videoObjectColourValues(pixels: Self.workingPixels($0, width: keyframe.depth.width, height: keyframe.depth.height,
                                                                    context: filter.context),
                                         depth: keyframe.depth.values, redLoss: scene.analysis.redLoss)
        }
        videoObjectCache.withLock { entries in
            entries.removeAll { $0.key == key }
            entries.append(VideoObjectCacheEntry(key: key, values: values))
            if entries.count > VideoObjectCacheEntry.capacity { entries.removeFirst(entries.count - VideoObjectCacheEntry.capacity) }
        }
        return values
    }

    func videoObjectColourValues(_ moment: VideoSceneMoment, settings: FilterSettings, filter: FilterEngine,
                                 preservesHDR: Bool) -> VideoObjectColourValues? {
        let a = videoObjectColourValues(moment.from, settings: settings, filter: filter, preservesHDR: preservesHDR)
        guard moment.amount > 0 else { return a }
        let b = videoObjectColourValues(moment.to, settings: settings, filter: filter, preservesHDR: preservesHDR)
        return VideoObjectColourValues.mixed(a, b, amount: moment.amount)
    }
}
