import CoreImage
import Vision

/// The subject lift (docs/SubjectEmphasis.md). It brightens the subject and follows with its chroma.
///
/// The defaults are the whole recipe. The product is one touch, so these values are the product:
/// nobody tunes them per photo. They were chosen on the five photos in `DeveloperMedia/subjectpicker`
/// and the E1 set, at each photo's own resolution (23 Oct 2026). Tier two at 0.5 read as processed;
/// 0.2 keeps the reef natural and still separates it. Tier three stays under tier two, or the
/// background would lead the foreground.
/// Nil on a plan means no lift, which is what the app ships until E6 turns it on.
struct SubjectLift: Sendable, Equatable {
    var mask: SubjectMask
    /// Lift strength, 0 to 0.9. L becomes `pow(L, 1 - strength)` at mask weight 1, so it cannot
    /// pass white, and the dark part of the subject moves most.
    var strength: Float = 0.18
    /// The most the chroma may grow, whatever `chromaExponent` asks for.
    var chromaCap: Float = 1.3
    /// Tier two: how much of the lift reaches pixels that are not open water but hold no Vision
    /// instance, such as a reef or a wreck. 0 is off, 1 treats them like a Vision subject.
    var tier2: Float = 0.2
    /// How much the sharpening and the clarity fade with distance, 0 to 1. At 1 the far end of the
    /// depth map gets none. A far subject carries less real detail, so sharpening it raises the veil.
    var textureFalloff: Float = 0.8
    /// Tier three: the same as tier two for pixels beyond `depthSplit`, the background reef.
    var tier3: Float = 0.1
    /// Where near becomes far, on the normalised depth map. 0 is nearest.
    var depthSplit: Float = 0.4
    /// The highlight pull for tiers two and three. A reef clips where a Vision subject does not.
    var highlights2: Float = 0.85
    var highlights3: Float = 0.85
    /// The lift's weight ramp, read on the mask. Below `maskLow` the lift is off, so it never reaches
    /// the water outside the outline. Equal values leave the mask as Vision built it.
    var maskLow: Float = 0.5
    var maskHigh: Float = 0.8
    /// Clarity inside the subject: the same idea at a wider radius, so it shapes the big forms.
    var clarity: Float = 0.6
    /// The clarity blur radius, as a share of the short side. The scene value is (5 + 3 x haze) / 480.
    var clarityRadius: Float = 6.0 / 480
    /// How much of the subject's highlight range above `highlightKnee` is taken back. 0 is off.
    var highlights: Float = 0.4
    /// Where the highlight pull starts, on OKLab L.
    var highlightKnee: Float = 0.75
    /// Sharpening inside the subject: the pixel's L minus its own small blur, added back. 0 is off.
    var detail: Float = 0.6
    /// The blur radius, as a share of the short side.
    var detailRadius: Float = 2.0 / 480
    /// The high-pass size where the sharpening starts to fade, and where it is off. A strong edge
    /// gets nothing, so an outline grows no halo.
    var detailEdgeLow: Float = 0.05
    var detailEdgeHigh: Float = 0.30
    /// Contrast inside the subject, around `contrastPivot`, on OKLab L. 0 leaves it alone.
    var contrast: Float = 0.15
    /// The L the contrast turns around. A constant, so the kernel keeps no per-frame statistic.
    var contrastPivot: Float = 0.5
    /// Chroma follows `(Lnew / L)` raised to this power. 1/3 is the cube root the first draft used.
    var chromaExponent: Float = 1.0 / 3
    /// Above this L the lift fades out, because the highlight shoulder has already run.
    var highlightStart: Float = 0.85
    /// Below this L the lift fades out, because a dark pixel is mostly noise.
    var noiseFloor: Float = 0.05
}

/// The photo's main subjects (Vision foreground instances, all of them) as a soft mask:
/// 0 is background, 1 is subject. Row 0 is the top row, as in NormalizedDepthMap.
///
/// The local veil measures the broad light around each pixel (RestorationEngine.restore). A bright
/// subject raised that light for the water beside it, so the veil took too much there and the water
/// around the subject turned into a dark band (O4 manta, 1 Oct 2026: band against the water above,
/// lightness -0.032; the source +0.005). With the mask, that light leaves the subject out.
struct SubjectMask: Sendable, Equatable {
    let width: Int
    let height: Int
    let values: [Float]

    /// A larger mask is a reef or a scene, not a subject (m5: the reef block was 31% of the frame).
    /// This is the local veil's cap. The subject lift uses `liftMaximumShare`.
    static let maximumShare: Float = 0.25
    /// The cap for the subject lift. Lifting a large subject is safe; taking the veil off one is not.
    /// m5's coral block (31%) is the photo's subject, so the veil cap rejected it (docs/SubjectEmphasis.md, E2).
    /// 0.5 matches `SubjectCandidates.maximumPickedShare`. Above half the frame it is a scene, not a subject.
    static let liftMaximumShare: Float = 0.5
    /// Below this the mask is noise.
    static let minimumShare: Float = 0.005
    /// Vision reads a small image; the mask is made at this long side.
    static let side: CGFloat = 1024

    /// Nil when Vision finds no subject, or the subjects cover too little or too much of the frame.
    /// `cap` is the largest share the caller accepts. The default is the local veil's cap.
    static func estimate(_ image: CIImage, cap: Float = maximumShare) -> SubjectMask? {
        guard let small = visionInput(image) else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: small, options: [:])
        guard (try? handler.perform([request])) != nil, let observation = request.results?.first,
              !observation.allInstances.isEmpty,
              let buffer = try? observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
        else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let row = CVPixelBufferGetBytesPerRow(buffer)
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent32Float,
              width > 1, height > 1, let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        var values = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            let line = (base + y * row).assumingMemoryBound(to: Float.self)
            for x in 0..<width { values[y * width + x] = line[x].isFinite ? min(1, max(0, line[x])) : 0 }
        }
        let share = values.reduce(0, +) / Float(values.count)
        guard share >= minimumShare, share <= cap else { return nil }
        return SubjectMask(width: width, height: height, values: values)
    }

    /// The image Vision reads: moved to the origin and scaled to `side`. Nil for an empty or infinite extent.
    static func visionInput(_ image: CIImage) -> CIImage? {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0, extent.width.isFinite, extent.height.isFinite else { return nil }
        let scale = min(1, side / max(extent.width, extent.height))
        return image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale)))
    }

    /// The mask as an image over `extent` (red holds the mask).
    func image(matching extent: CGRect) -> CIImage {
        let data = values.withUnsafeBytes { Data($0) }
        let mask = CIImage(bitmapData: data, bytesPerRow: width * MemoryLayout<Float>.size,
                           size: CGSize(width: width, height: height), format: .Rf, colorSpace: nil)
        let scaled = mask.transformed(by: CGAffineTransform(scaleX: extent.width / CGFloat(width),
                                                            y: extent.height / CGFloat(height)))
        return scaled.transformed(by: CGAffineTransform(translationX: extent.minX - scaled.extent.minX,
                                                        y: extent.minY - scaled.extent.minY))
    }
}
