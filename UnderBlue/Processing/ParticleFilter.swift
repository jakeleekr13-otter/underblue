import CoreImage
import CoreMedia
import CoreVideo
import Metal

/// Removes marine snow from video: small bright specks that drift through the water.
///
/// A pixel is changed only when every test passes:
/// 1. Small, bright and isolated: its blurred luma is brighter than every point on a ring of `ringRadius` px
///    around it, by more than `floor` and more than `spreadGain` times the ring's own spread. Its contrast
///    over the ring mean must stay below `maxContrast`. Anything wider than the ring, any line or edge that crosses it, any spot in busy texture
///    and any very bright highlight fails this test.
/// 2. Drifting: camera motion is removed (global shift, then per 64 px block). A neighbour frame is usable
///    only when two rings around the spot (`contextRadius` and twice that) look the same there. A spot on a moving fish
///    or on badly aligned coral makes every neighbour unusable, so it is kept.
///    The spot is drifting when a usable neighbour has no peak of `matchRatio` of its strength (and at
///    least half its threshold) within 1 px. Slow specks that stay within 1 px are kept.
/// 3. Background fill: pixels within 4 px of a drifting spot take the mean of the unmarked ring pixels
///    around them (`fillRadius`). This also lifts the dark sharpening halo that cameras leave around specks.
///
/// Streaming use, same shape as `TemporalDenoiser`: `push` each frame in presentation order,
/// use every frame it returns, then call `finish` once. It holds 1 previous and 2 next frames, plus the newest
/// frame while its GPU work runs, so output lags input by 3 frames. Frame count, order and times never change.
/// Not thread-safe: one instance per export, called from one task.
final class ParticleFilter {
    struct Frame {
        let image: CIImage
        let time: CMTime
    }

    /// Luma values are the square root of linear luma, 0...1. 1/219 is about one 8-bit video code.
    struct Settings: Sendable {
        var ringRadius: Float = 5
        var fillRadius: Float = 7
        var contextRadius: Float = 6
        var floor: Float = 4 / 219
        var spreadGain: Float = 2
        /// Spots brighter than this are never touched: in ambient light they are fish highlights, coral tips
        /// or bubbles, not marine snow. Strobe-lit backscatter above it is left alone too.
        var maxContrast: Float = 30 / 219
        var matchRatio: Float = 0.08
        /// A neighbour is usable when its mean ring difference is below this share of the spot's contrast
        /// plus half of `floor`. Texture does not widen it, so badly aligned coral is not usable.
        var contextTolerance: Float = 0.03
    }
    let settings: Settings
    private let context: CIContext
    private let lumaKernel: CIColorKernel
    private let peakKernel: CIKernel
    private let maskKernel: CIKernel
    private let fillKernel: CIKernel
    private let tileKernel: CIKernel
    private let motion: MotionEstimator
    private var pool: CVPixelBufferPool?
    private var textureCache: CVMetalTextureCache?
    /// The last frame's probe, the start of the next motion search.
    private var probe: MotionEstimator.Probe?
    private var window: [Entry] = []
    private var cursor = 0
    private let previousCount = 1, nextCount = 2

    private struct Entry {
        let image: CIImage
        /// r: spot contrast, g: contrast needed, b: blurred luma. Valid once `work` is nil and `usable` is true.
        let peak: CIImage
        let time: CMTime
        var motionToNext: MotionField?
        /// GPU work still running: the peak render, the probe and the search from the previous frame.
        var work: Work?
        var usable: Bool
    }

    private struct Work {
        let commands: any MTLCommandBuffer
        /// Keeps the Metal view of the peak buffer alive until the GPU wrote it.
        let target: CVMetalTexture
        let vectors: (any MTLBuffer)?
    }

    /// Returns nil when the Metal kernels fail to compile. The caller then uses frames unchanged.
    init?(context: CIContext, settings: Settings = Settings()) {
        guard let kernels = try? CIKernel.kernels(withMetalString: Self.metalSource),
              let luma = kernels.first(where: { $0.name == "UnderBlueSpeckLuma" }) as? CIColorKernel,
              let peak = kernels.first(where: { $0.name == "UnderBlueSpeckPeak" }),
              let mask = kernels.first(where: { $0.name == "UnderBlueSpeckMask" }),
              let fill = kernels.first(where: { $0.name == "UnderBlueSpeckFill" }),
              let tiles = kernels.first(where: { $0.name == "UnderBlueSpeckTiles" }),
              let motion = MotionEstimator() else { return nil }
        self.context = context
        self.settings = settings
        lumaKernel = luma; peakKernel = peak; maskKernel = mask; fillKernel = fill; tileKernel = tiles
        self.motion = motion
    }

    /// Adds one frame. Returns the frame that is now ready, or nil while the look-ahead fills.
    /// A frame smaller than 64x64 or of another size than the first passes through unchanged.
    func push(_ image: CIImage, at time: CMTime) -> Frame? {
        if let first = window.first, first.image.extent.size != image.extent.size { return Frame(image: image, time: time) }
        guard let entry = prepare(image, at: time) else { return Frame(image: image, time: time) }
        window.append(entry)
        guard window.count - cursor > nextCount + 1 else { return nil }
        return emit()
    }

    /// Flushes the look-ahead. Call once after the last `push`.
    func finish() -> [Frame] {
        var frames: [Frame] = []
        while cursor < window.count { frames.append(emit()) }
        window.removeAll(); cursor = 0; probe = nil
        return frames
    }

    /// Waits for the GPU work of every entry up to `last` and takes its motion field.
    private func settle(through last: Int) {
        for i in window.indices where i <= last {
            guard let work = window[i].work else { continue }
            work.commands.waitUntilCompleted()
            window[i].work = nil
            window[i].usable = work.commands.status == .completed
            if window[i].usable, i > 0, let v = work.vectors {
                let e = window[i].image.extent
                window[i - 1].motionToNext = motion.field(v, width: Int(e.width), height: Int(e.height))
            }
        }
        if let textureCache { CVMetalTextureCacheFlush(textureCache, 0) }
    }

    private func emit() -> Frame {
        settle(through: min(window.count - 1, cursor + nextCount))
        let source = window[cursor]
        var neighbours: [(CIImage, MotionField)] = []
        if cursor > 0, window[cursor - 1].usable, let m = window[cursor - 1].motionToNext { neighbours.append((window[cursor - 1].peak, -m)) }
        var chained: MotionField?
        for i in (cursor + 1)..<min(window.count, cursor + 1 + nextCount) {
            guard window[i].usable, let step = window[i - 1].motionToNext else { break }
            chained = chained.map { $0 + step } ?? step
            neighbours.append((window[i].peak, chained!))
        }
        let output = source.usable ? filtered(source, neighbours: neighbours) : source.image
        cursor += 1
        let drop = max(0, cursor - previousCount)
        if drop > 0 { window.removeFirst(drop); cursor -= drop }
        return Frame(image: output, time: source.time)
    }

    private func filtered(_ source: Entry, neighbours: [(CIImage, MotionField)]) -> CIImage {
        guard !neighbours.isEmpty else { return source.image }
        let s = settings
        let extent = source.image.extent
        let empty = CIImage(color: .clear).cropped(to: extent)
        var peaks = neighbours.map(\.0)
        var fields = neighbours.map(\.1)
        while peaks.count < 3 { peaks.append(empty); fields.append(fields[0]) }
        let flowA = flowImage(fields[0], fields[1], extent: extent), flowB = flowImage(fields[2], fields[2], extent: extent)
        let reach = CGFloat(2 * s.contextRadius + 6)
        let cur = source.peak
        // The blocks cover whole 64 px cells from the top. Core Image rows start at the bottom.
        let flowExtent = flowA.extent, covered = flowExtent.height * CGFloat(MotionField.block)
        let tileExtent = CGRect(x: 0, y: 0, width: (extent.width / 8).rounded(.up), height: (extent.height / 8).rounded(.up))
        guard let tiles = tileKernel.apply(extent: tileExtent, roiCallback: { _, r in
                  CGRect(x: extent.minX + 8 * r.minX, y: extent.minY + 8 * r.minY, width: 8 * r.width, height: 8 * r.height) },
                  arguments: [cur, CIVector(x: extent.minX, y: extent.minY)]),
              let mask = maskKernel.apply(extent: extent, roiCallback: { i, r in
                  switch i {
                  case 0: r.insetBy(dx: -reach, dy: -reach).intersection(extent)
                  case 1...3: r.insetBy(dx: -reach - 256, dy: -reach - 256).intersection(extent)
                  case 4, 5: flowExtent
                  default: tileExtent
                  } },
                  arguments: [cur, peaks[0], peaks[1], peaks[2], flowA, flowB, tiles,
                              CIVector(x: CGFloat(neighbours.count), y: CGFloat(s.matchRatio),
                                       z: CGFloat(s.contextRadius), w: CGFloat(s.contextTolerance)),
                              CIVector(x: CGFloat(s.floor), y: 0, z: 0, w: 0),
                              CIVector(x: extent.minX, y: extent.minY, z: extent.maxX, w: extent.maxY),
                              CIVector(x: extent.minX, y: extent.maxY - covered, z: flowExtent.width, w: flowExtent.height)]),
              let out = fillKernel.apply(extent: extent, roiCallback: { _, r in
                  r.insetBy(dx: CGFloat(-s.fillRadius - 2), dy: CGFloat(-s.fillRadius - 2)) },
                  arguments: [source.image.clampedToExtent(), mask.clampedToExtent(), CIVector(x: CGFloat(s.fillRadius), y: 0, z: 0, w: 0)])
        else { return source.image }
        return out.cropped(to: extent)
    }

    /// Two motion fields as one small image, one texel per block, in Core Image axes (y up).
    /// The mask kernel samples it bilinearly between block centres.
    private func flowImage(_ a: MotionField, _ b: MotionField, extent: CGRect) -> CIImage {
        var values = [Float](repeating: 0, count: a.gw * a.gh * 4)
        for row in 0..<a.gh { for x in 0..<a.gw {
            let src = row * a.gw + x, dst = ((a.gh - 1 - row) * a.gw + x) * 4
            values[dst] = a.vectors[src].x; values[dst + 1] = -a.vectors[src].y
            values[dst + 2] = b.vectors[src].x; values[dst + 3] = -b.vectors[src].y
        }}
        let data = values.withUnsafeBytes { Data($0) }
        return CIImage(bitmapData: data, bytesPerRow: a.gw * 16, size: CGSize(width: a.gw, height: a.gh),
                       format: .RGBAf, colorSpace: nil).samplingLinear()
    }

    /// Encodes and commits the GPU work for one frame: the peak map, the 1/4-scale luma probe and the motion
    /// from the previous frame to this one. Nothing waits here; `settle` collects the result later.
    /// Returns nil only for a frame too small to filter. When the GPU work cannot be set up, the entry is
    /// marked unusable and the frame later passes through unchanged, in order.
    private func prepare(_ image: CIImage, at time: CMTime) -> Entry? {
        let extent = image.extent
        let w = Int(extent.width), h = Int(extent.height)
        guard w >= 64, h >= 64 else { return nil }
        let s = settings
        let toOrigin = CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
        if textureCache == nil { CVMetalTextureCacheCreate(nil, nil, motion.device, nil, &textureCache) }
        var wrapped: CVMetalTexture?
        guard let luma = lumaKernel.apply(extent: extent, arguments: [image]),
              let peakRecipe = peakKernel.apply(extent: extent, roiCallback: { _, r in
                  r.insetBy(dx: CGFloat(-s.ringRadius - 2), dy: CGFloat(-s.ringRadius - 2)) },
                  arguments: [luma.clampedToExtent().applyingGaussianBlur(sigma: 0.8),
                              CIVector(x: CGFloat(s.ringRadius), y: CGFloat(s.floor), z: CGFloat(s.spreadGain), w: CGFloat(s.maxContrast))]),
              let buffer = peakBuffer(width: w, height: h), let textureCache,
              CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, buffer, nil, .rgba16Float, w, h, 0, &wrapped) == kCVReturnSuccess,
              let wrapped, let texture = CVMetalTextureGetTexture(wrapped), let cb = motion.queue.makeCommandBuffer()
        else { return Entry(image: image, peak: image, time: time, usable: false) }
        let destination = CIRenderDestination(mtlTexture: texture, commandBuffer: cb)
        destination.colorSpace = nil
        destination.isFlipped = true
        let previous = window.last.flatMap { $0.usable ? probe : nil }
        guard (try? context.startTask(toRender: peakRecipe.transformed(by: toOrigin), from: CGRect(x: 0, y: 0, width: w, height: h),
                                      to: destination, at: .zero)) != nil,
              let current = motion.probe(luma.transformed(by: toOrigin), width: w, height: h, context: context, into: cb)
        else { probe = nil; return Entry(image: image, peak: image, time: time, usable: false) }
        let vectors = previous.flatMap { motion.encodeField(from: $0, to: current, into: cb) }
        cb.commit()
        probe = current
        var peak = CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()])
        if extent.origin != .zero { peak = peak.transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY)) }
        return Entry(image: image, peak: peak, time: time, work: Work(commands: cb, target: wrapped, vectors: vectors), usable: true)
    }

    private func peakBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        if pool == nil {
            let attributes: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_64RGBAHalf,
                                             kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
                                             kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                                             kCVPixelBufferMetalCompatibilityKey as String: true]
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        }
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { return nil }
        return buffer
    }
}
