import CoreImage

extension ColorCorrection {
    /// Every stored value, for mixing two scenes. A new stored value must be added here, or a scene
    /// change jumps in that value at the end of the fade. A test counts them against the struct.
    static var mixedScalars: [WritableKeyPath<Self, Float>] {
        [\.redRebuild, \.redGateLow, \.redGateHigh, \.subjectRed, \.waterRedness, \.waterSaturation, \.waterChroma,
         \.waterType, \.redCeiling, \.violetGuard, \.midLift, \.toneCurve, \.tonePivot, \.brightness, \.contrast,
         \.saturation, \.shadowLift, \.highlightAmount, \.clarity, \.clarityRadius, \.definition, \.definitionRadius,
         \.detail, \.detailFloor, \.detailRadius, \.warmth, \.vibrance, \.physicalWeight, \.referenceStrength,
         \.lightGradient]
    }
    static var mixedVectors: [WritableKeyPath<Self, SIMD3<Float>>] {
        [\.castGains, \.waterTone, \.subjectTone, \.neutralGains, \.waterLit, \.referenceGains]
    }

    func mixed(with other: Self, amount: Float) -> Self {
        if amount <= 0 { return self }
        if amount >= 1 { return other }
        var v = self
        for key in Self.mixedScalars { v[keyPath: key] += (other[keyPath: key] - self[keyPath: key]) * amount }
        for key in Self.mixedVectors { v[keyPath: key] += (other[keyPath: key] - self[keyPath: key]) * amount }
        return v
    }
}

extension RestorationPlan {
    /// Mixes two scene-level plans. Both carry one constant depth, so their depth maps mix too; maps of
    /// different sizes keep the nearer plan's map. Confidence mixes without a dip in the middle.
    func mixed(with other: RestorationPlan, amount: Float) throws -> RestorationPlan {
        func mix(_ a: Float, _ b: Float) -> Float { a + (b - a) * amount }
        func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> { a + (b - a) * amount }
        let nearest = amount < 0.5 ? self : other
        let mixedDepth = self.depth.width == other.depth.width && self.depth.height == other.depth.height
            ? try NormalizedDepthMap(width: self.depth.width, height: self.depth.height,
                                     values: zip(self.depth.values, other.depth.values).map { mix($0, $1) })
            : nearest.depth
        let mixedLimits = RestorationLimits(transmissionFloor: mix(self.limits.transmissionFloor, other.limits.transmissionFloor),
                                       maximumGain: mix(self.limits.maximumGain, other.limits.maximumGain),
                                       highlightStart: mix(self.limits.highlightStart, other.limits.highlightStart),
                                       highlightEnd: mix(self.limits.highlightEnd, other.limits.highlightEnd),
                                       maximumOutput: mix(self.limits.maximumOutput, other.limits.maximumOutput))
        var plan = RestorationPlan(
            depth: mixedDepth, depthSource: nearest.depthSource,
            depthStatistics: DepthStatistics(minimum: mix(depthStatistics.minimum, other.depthStatistics.minimum),
                                             maximum: mix(depthStatistics.maximum, other.depthStatistics.maximum),
                                             median: mix(depthStatistics.median, other.depthStatistics.median)),
            backscatterInfinity: mix(backscatterInfinity, other.backscatterInfinity),
            betaDirect: mix(betaDirect, other.betaDirect),
            betaBackscatter: mix(betaBackscatter, other.betaBackscatter),
            confidence: mix(confidence, other.confidence),
            limits: mixedLimits,
            transmissionFloorPixelPercentage: mix(transmissionFloorPixelPercentage, other.transmissionFloorPixelPercentage),
            maximumGainPixelPercentage: mix(maximumGainPixelPercentage, other.maximumGainPixelPercentage),
            depthConfidence: mix(depthConfidence, other.depthConfidence),
            waterFitConfidence: mix(waterFitConfidence, other.waterFitConfidence),
            temporalConfidence: mix(temporalConfidence, other.temporalConfidence),
            channelRecoverability: mix(channelRecoverability, other.channelRecoverability))
        plan.veilLevel = mix(veilLevel, other.veilLevel)
        plan.residualCast = mix(residualCast, other.residualCast)
        return plan
    }
}
