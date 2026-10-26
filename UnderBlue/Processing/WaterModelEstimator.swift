import CoreImage

struct WaterModelEstimator {
    func estimate(image: CIImage, depth: DepthEstimate, legacy: WaterAnalysis, context: CIContext) throws -> RestorationPlan {
        let map = depth.map
        let pixels = try pixels(from: image, width: map.width, height: map.height, context: context)
        let candidates = darkCandidates(pixels: pixels, depth: map.values)
        guard candidates.count >= 24 else { throw RestorationError.waterModelFitFailed }

        var infinity = SIMD3<Float>(repeating: 0)
        var betaBackscatter = SIMD3<Float>(repeating: 0)
        var fitQuality: Float = 0
        for channel in 0..<3 {
            let fit = fitBackscatter(channel: channel, candidates: candidates, pixels: pixels, depth: map.values)
            infinity[channel] = fit.infinity
            betaBackscatter[channel] = fit.beta
            fitQuality += fit.quality / 3
        }

        let fittedDirect = fitDirectAttenuation(pixels: pixels, depth: map.values,
                                                infinity: infinity, betaBackscatter: betaBackscatter)
        let priors = SIMD3<Float>(0.38 + legacy.redLoss * 0.9,
                                  0.20 + legacy.cyanDominance * 0.22,
                                  0.13 + legacy.cyanDominance * 0.10)
        var betaDirect = fittedDirect.value * 0.35 + priors * 0.65
        betaDirect = SIMD3(min(1.55, max(0.18, betaDirect.x)),
                           min(0.90, max(0.08, betaDirect.y)),
                           min(0.65, max(0.05, betaDirect.z)))
        // Channel-unequal attenuation needs a measured cast. A neutral scene gets equal
        // attenuation, so its greys stay grey; the spread grows with the cast.
        let cast = legacy.castStrength
        betaDirect = spread(betaDirect, by: cast)

        // darkCandidates keeps at most 256 per depth bin, so full coverage is 8 x 256 samples.
        let candidateCoverage = min(1, Float(candidates.count) / Float(8 * 256))
        let confidence = min(0.9, max(0, depth.confidence * sqrt(max(0, fitQuality))
                                     * (0.55 + 0.45 * candidateCoverage)
                                     * (0.7 + 0.3 * fittedDirect.quality)))
        guard confidence.isFinite else { throw RestorationError.waterModelFitFailed }

        // When red information is nearly absent, stronger amplification mostly reveals noise.
        let redSurvival = min(1, max(0, 1 - legacy.redLoss))
        let recoverability = channelRecoverability(pixels: pixels, depth: map.values, infinity: infinity,
                                                   betaBackscatter: betaBackscatter,
                                                   redSurvival: redSurvival)
        let limits = RestorationLimits(maximumGain: spread(SIMD3(1.32 + 0.45 * redSurvival, 1.55, 1.45), by: cast))
        let hits = limitHitPercentages(depth: map.values, betaDirect: betaDirect, limits: limits)
        var plan = RestorationPlan(depth: map, depthSource: depth.source, depthStatistics: depth.statistics,
                               backscatterInfinity: finite(infinity), betaDirect: finite(betaDirect),
                               betaBackscatter: finite(betaBackscatter), confidence: confidence,
                               limits: limits, transmissionFloorPixelPercentage: hits.floor,
                               maximumGainPixelPercentage: hits.gain, depthConfidence: depth.confidence,
                               waterFitConfidence: sqrt(max(0, fitQuality)),
                               channelRecoverability: recoverability)
        plan.veilLevel = (legacy.waterColor * ColorCorrection.luma).sum()
        return plan
    }

    private func pixels(from image: CIImage, width: Int, height: Int, context: CIContext) throws -> [SIMD3<Float>] {
        let translated = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        let scaled = translated.transformed(by: CGAffineTransform(scaleX: CGFloat(width) / image.extent.width,
                                                                  y: CGFloat(height) / image.extent.height))
        var rgba = [Float](repeating: 0, count: width * height * 4)
        context.render(scaled, toBitmap: &rgba, rowBytes: width * 4 * MemoryLayout<Float>.size,
                       bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBAf,
                       colorSpace: FilterEngine.workingSpace)
        var result: [SIMD3<Float>] = []
        result.reserveCapacity(width * height)
        for index in stride(from: 0, to: rgba.count, by: 4) {
            let value = SIMD3(rgba[index], rgba[index + 1], rgba[index + 2])
            result.append(finite(value))
        }
        return result
    }

    private func darkCandidates(pixels: [SIMD3<Float>], depth: [Float]) -> [Int] {
        var selected: [Int] = []
        for bin in 0..<8 {
            let low = Float(bin) / 8, high = Float(bin + 1) / 8
            var indices = depth.indices.filter { depth[$0] >= low && (bin == 7 ? depth[$0] <= high : depth[$0] < high) }
            indices = indices.filter {
                let p = pixels[$0], luma = p.x * 0.2126 + p.y * 0.7152 + p.z * 0.0722
                return luma > 0.008 && luma < 0.82 && max(p.x, p.y, p.z) < 1
            }
            indices.sort {
                let a = pixels[$0], b = pixels[$1]
                return a.x + a.y + a.z < b.x + b.y + b.z
            }
            // A few hundred lower-envelope samples per bin are enough for the
            // three-parameter fit and keep preparation time independent of photo size.
            selected.append(contentsOf: indices.prefix(min(256, max(3, indices.count / 5))))
        }
        return selected
    }

    private func fitBackscatter(channel: Int, candidates: [Int], pixels: [SIMD3<Float>], depth: [Float])
        -> (infinity: Float, beta: Float, quality: Float) {
        var best = (infinity: Float(0.08), beta: Float(0.5), error: Float.greatestFiniteMagnitude)
        for step in 0...47 {
            let beta = 0.12 + Float(step) * 0.05
            var numerator: Float = 0, denominator: Float = 0
            for index in candidates {
                let factor = 1 - exp(-beta * depth[index])
                numerator += factor * pixels[index][channel]
                denominator += factor * factor
            }
            let infinity = min(0.9, max(0.005, numerator / max(denominator, 1e-6)))
            var errors: [Float] = []
            errors.reserveCapacity(candidates.count)
            for index in candidates {
                let prediction = infinity * (1 - exp(-beta * depth[index]))
                errors.append(abs(prediction - pixels[index][channel]))
            }
            errors.sort()
            let error = errors[errors.count / 2]
            if error < best.error { best = (infinity, beta, error) }
        }
        let quality = min(1, max(0, 1 - best.error / max(0.04, best.infinity)))
        return (best.infinity, best.beta, quality)
    }

    private func fitDirectAttenuation(pixels: [SIMD3<Float>], depth: [Float], infinity: SIMD3<Float>,
                                      betaBackscatter: SIMD3<Float>) -> (value: SIMD3<Float>, quality: Float) {
        var result = SIMD3<Float>(repeating: 0)
        var usableChannels: Float = 0
        for channel in 0..<3 {
            var points: [(Float, Float)] = []
            for bin in 0..<8 {
                let low = Float(bin) / 8, high = Float(bin + 1) / 8
                var values: [Float] = []
                for index in depth.indices where depth[index] >= low && (bin == 7 ? depth[index] <= high : depth[index] < high) {
                    let backscatter = infinity[channel] * (1 - exp(-betaBackscatter[channel] * depth[index]))
                    let direct = pixels[index][channel] - backscatter
                    if direct.isFinite && direct > 0.005 && direct < 1 { values.append(direct) }
                }
                guard values.count >= 8 else { continue }
                values.sort()
                let envelope = values[Int(Float(values.count - 1) * 0.8)]
                points.append(((low + high) / 2, log(max(1e-5, envelope))))
            }
            guard points.count >= 4 else { continue }
            let meanX = points.map(\.0).reduce(0, +) / Float(points.count)
            let meanY = points.map(\.1).reduce(0, +) / Float(points.count)
            let numerator = points.reduce(Float(0)) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
            let denominator = points.reduce(Float(0)) { $0 + ($1.0 - meanX) * ($1.0 - meanX) }
            result[channel] = max(0, -numerator / max(denominator, 1e-6))
            usableChannels += 1
        }
        return (finite(result), usableChannels / 3)
    }

    private func limitHitPercentages(depth: [Float], betaDirect: SIMD3<Float>, limits: RestorationLimits)
        -> (floor: Float, gain: Float) {
        var floorHits = 0, gainHits = 0
        for z in depth {
            var pixelFloor = false, pixelGain = false
            for channel in 0..<3 {
                let transmission = exp(-betaDirect[channel] * z)
                pixelFloor = pixelFloor || transmission <= limits.transmissionFloor
                pixelGain = pixelGain || 1 / max(transmission, limits.transmissionFloor) >= limits.maximumGain[channel]
            }
            if pixelFloor { floorHits += 1 }
            if pixelGain { gainHits += 1 }
        }
        let count = Float(max(1, depth.count))
        return (Float(floorHits) * 100 / count, Float(gainHits) * 100 / count)
    }

    private func channelRecoverability(pixels: [SIMD3<Float>], depth: [Float], infinity: SIMD3<Float>,
                                       betaBackscatter: SIMD3<Float>, redSurvival: Float) -> SIMD3<Float> {
        var result = SIMD3<Float>(repeating: 0)
        for channel in 0..<3 {
            var direct: [Float] = []
            direct.reserveCapacity(min(4096, pixels.count))
            let stride = max(1, pixels.count / 4096)
            for index in Swift.stride(from: 0, to: pixels.count, by: stride) {
                let backscatter = infinity[channel] * (1 - exp(-betaBackscatter[channel] * depth[index]))
                let signal = pixels[index][channel] - backscatter
                if signal.isFinite && signal > 0 { direct.append(signal) }
            }
            direct.sort()
            let median = direct.isEmpty ? 0 : direct[direct.count / 2]
            result[channel] = min(1, max(0.08, (median - 0.004) / 0.075))
        }
        result.x = min(result.x, max(0.12, redSurvival))
        return finite(result)
    }

    /// Channel mean plus `amount` of each channel's difference from it.
    private func spread(_ value: SIMD3<Float>, by amount: Float) -> SIMD3<Float> {
        let mean = (value.x + value.y + value.z) / 3
        return SIMD3(repeating: mean) + (value - SIMD3(repeating: mean)) * min(1, max(0, amount))
    }

    private func finite(_ value: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(value.x.isFinite ? value.x : 0, value.y.isFinite ? value.y : 0, value.z.isFinite ? value.z : 0)
    }
}

/// Open water whose veil the fit could not measure (jellyfish lake photo, `Tune_26_Oct`, 26 Oct 2026).
/// The frame is all veil and the veil never levels off with depth, so the fit stops at its 0.9 limit in every channel.
/// The veil it removes then follows the depth map closely. The depth model drew a slope in plain water (1.0 to 0.53),
/// so the water came out patchy and a grey band ringed the swimmer. Such water gets the far depth of the open water
/// (`farWaterPercentile`). Subjects keep their depth, so the pink fins keep their colour. The median depth (0.73) was
/// tried first: the object colour step reads water as depth above 0.8, so it lost its water and the fins turned
/// blue-white (hue 30 to 230), and it tints depth 0.6 to 0.9 as near, so the flat water would take the object gains.
/// The fit itself cannot be trusted either, so the physical restoration is taken away by the same weight. Kept, the
/// near swimmer and the far water split apart and the glow beside the legs grew (ring minus far water +0.20 L; the
/// source has +0.10). Without it the glow is +0.10, the water hue spans 197 to 214, and the fins stay pink (hue 40). A fit below the limit in any channel is left as it is:
/// in 57 test photos only this one had all three channels at the limit (one or two channels: 25 photos).
extension WaterModelEstimator {
    /// The smallest fitted veil channel over which the flattening turns on. The nearest other test photo, 8682
    /// (0.856), got scattered pixel jumps from a weight of 0.04 with 0.85 to 0.9, so the ramp starts at 0.88.
    static let unsaturatedVeil: ClosedRange<Float> = 0.88...0.9
    /// The water share over which a pixel counts as open water. The fins and legs read 0.75 (median), the water 0.99 or more.
    static let flatWaterShare: ClosedRange<Float> = 0.9...0.98
    /// The open water's depth that all of it gets.
    static let farWaterPercentile: Float = 0.9

    static func flatteningWeight(_ plan: RestorationPlan) -> Float {
        smoothstep(unsaturatedVeil, plan.backscatterInfinity.min())
    }

    /// `waterShare` is the share map (alpha of FilterEngine.waterShare) at the depth map's size.
    static func flatteningOpenWater(_ plan: RestorationPlan, waterShare: [Float]) -> RestorationPlan {
        let weight = flatteningWeight(plan)
        guard weight > 0, waterShare.count == plan.depth.values.count else { return plan }
        let open = zip(waterShare, plan.depth.values).filter { $0.0 >= flatWaterShare.upperBound }.map(\.1).sorted()
        // Too little open water to measure: nothing to flatten.
        guard Float(open.count) >= Float(waterShare.count) * SubjectTiers.minimumOpenWaterShare, !open.isEmpty else { return plan }
        let water = open[min(open.count - 1, Int(Float(open.count - 1) * farWaterPercentile))]
        let values = zip(plan.depth.values, waterShare).map { depth, share in
            depth + (water - depth) * weight * smoothstep(flatWaterShare, share)
        }
        guard let flat = try? NormalizedDepthMap(width: plan.depth.width, height: plan.depth.height, values: values) else { return plan }
        var result = plan.trusting(1 - weight)
        result.depth = flat
        return result
    }

    /// The same on a photo: its water share is made at the depth map's size with `correction` (Natural's).
    /// Ordinary photos return at once, without the render.
    static func flatteningOpenWater(_ plan: RestorationPlan, image: CIImage, correction: ColorCorrection,
                                    filter: FilterEngine) -> RestorationPlan {
        guard flatteningWeight(plan) > 0, !image.extent.isEmpty else { return plan }
        let d = plan.depth
        let small = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY)
            .concatenating(CGAffineTransform(scaleX: CGFloat(d.width) / image.extent.width, y: CGFloat(d.height) / image.extent.height)))
        guard let share = filter.waterShare(small, correction: correction) else { return plan }
        let values = SubjectTiers.channel(share, 3, width: d.width, height: d.height, context: filter.context)
        return flatteningOpenWater(plan, waterShare: values)
    }

    private static func smoothstep(_ range: ClosedRange<Float>, _ value: Float) -> Float {
        let t = min(1, max(0, (value - range.lowerBound) / (range.upperBound - range.lowerBound)))
        return t * t * (3 - 2 * t)
    }
}
