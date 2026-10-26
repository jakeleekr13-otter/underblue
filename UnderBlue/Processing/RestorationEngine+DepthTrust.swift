import CoreImage

/// How far the depth map shows where the water is (docs/RestorationExperiments.md, B2).
extension RestorationEngine {
    /// How far the depth map can be trusted as a water map (docs/RestorationExperiments.md, B2): the correlation of
    /// depth with a second map at depth-map size. The frame version below passes the luma output of the share kernel.
    static func depthTrust(depth: [Float], share: [Float]) -> Float {
        guard depth.count == share.count, depth.count > 100 else { return 0 }
        let n = Float(depth.count)
        let md = depth.reduce(0, +) / n, ms = share.reduce(0, +) / n
        var sdd: Float = 0, sss: Float = 0, sds: Float = 0
        for (d, w) in zip(depth, share) where d.isFinite && w.isFinite {
            sdd += (d - md) * (d - md); sss += (w - ms) * (w - ms); sds += (d - md) * (w - ms)
        }
        guard sdd > 1e-6, sss > 1e-6 else { return 0 }
        let t = min(1, max(0, (sds / (sdd * sss).squareRoot() - FinishingMath.depthTrustLow) / (FinishingMath.depthTrustHigh - FinishingMath.depthTrustLow)))
        return t * t * (3 - 2 * t)
    }

    /// depthTrust for a frame, from the share kernel's output on the frame scaled to the depth map (one small render).
    /// It reads the kernel's LUMA (channel 0), not the share (alpha). That was a slip, but it is the tested rule: with the
    /// share, the sunfish (AquaColorFix O3, r 0.67 luma / 0.32 share) and the chart reef (O6, 0.63 / 0.35) lost depth trust
    /// and turned teal (pairs 1-5 10.53 to 10.63, chart grey 0.010 to 0.029, 26 Oct 2026). The sun stills stay untrusted
    /// either way (luma 0.00 to 0.08). Where depth and brightness agree, depth is used.
    func depthTrust(_ image: CIImage, plan: RestorationPlan, correction: ColorCorrection, filter: FilterEngine) -> Float {
        depthTrust(image, depth: plan.depth, correction: correction, filter: filter)
    }

    /// `restored` with its subject light removal scaled by the depth trust: none at 0, all of it at 1 (combined()).
    static func trusting(_ restored: ColorCorrection, depthTrust: Float) -> ColorCorrection {
        var v = restored
        v.subjectTone = SIMD3(repeating: 1) + (restored.subjectTone - SIMD3(repeating: 1)) * min(1, max(0, depthTrust))
        return v
    }

    /// depthTrust on a depth map of the caller's: a video scene's keyframe, whose plan holds one constant depth.
    func depthTrust(_ image: CIImage, depth: NormalizedDepthMap, correction: ColorCorrection, filter: FilterEngine) -> Float {
        let dw = depth.width, dh = depth.height
        guard dw > 0, dh > 0, !image.extent.isEmpty,
              let share = filter.waterShare(FilterEngine.downscaled(image, maxPixel: CGFloat(max(dw, dh)) * 2), correction: correction)
        else { return 0 }
        let shares = Self.workingPixels(share, width: dw, height: dh, context: filter.context).map(\.x)
        return Self.depthTrust(depth: depth.values, share: shares)
    }

    /// The frame scaled to `width` x `height`, as linear Rec.2020 pixels (row 0 on top, as the depth map).
    static func workingPixels(_ frame: CIImage, width: Int, height: Int, context: CIContext) -> [SIMD3<Float>] {
        let small = frame.transformed(by: CGAffineTransform(translationX: -frame.extent.minX, y: -frame.extent.minY)
            .concatenating(CGAffineTransform(scaleX: CGFloat(width) / frame.extent.width, y: CGFloat(height) / frame.extent.height)))
        var raw = [Float](repeating: 0, count: width * height * 4)
        context.render(small, toBitmap: &raw, rowBytes: width * 16, bounds: CGRect(x: 0, y: 0, width: width, height: height),
                       format: .RGBAf, colorSpace: FilterEngine.workingSpace)
        return (0..<(width * height)).map { SIMD3(raw[$0 * 4], raw[$0 * 4 + 1], raw[$0 * 4 + 2]) }
    }
}
