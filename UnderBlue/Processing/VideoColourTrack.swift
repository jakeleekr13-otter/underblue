import AVFoundation
import CoreImage

/// Takes short colour pulses of the camera out of a clip, frame by frame.
/// In the napoleon wrasse clip (Tune_26_Oct, 26 Oct 2026) the camera's red rose 2.8x for 10 frames
/// and came back, while green stayed. The scene values hold still, so the correction passed the pulse
/// on: the grey fish and the sand turned pink for those frames (AquaColorFix shows the same).
/// Each frame's mean colour is compared with the median of the frames around it (`window`). A change
/// that lasts shorter than half the window is taken out; a longer one, as a new scene, stays.
/// Brightness is kept: only the colour balance of the frame moves.
/// The gains are per channel of Rec. 709, the camera's own primaries. Per channel of the Rec. 2020 working
/// space they took out only part of the pulse: the fish stayed pink in 8 of 10 frames (26 Oct 2026).
struct VideoColourTrack: Sendable, Equatable {
    let times: [Double]
    let gains: [SIMD3<Float>]

    /// Seconds, centred on the frame.
    static let window: Double = 1
    /// Added to each channel's share of the luminance before the ratio. Without it a channel near zero
    /// (blue water with no red at all) turns noise into gains of 2x and more: four of the test clips did.
    /// With it those clips stay within 2% and the napoleon pulse is still taken out (26 Oct 2026).
    static let floor: Float = 0.05
    /// Gains closer to 1 than this are left out. The mean of a steady clip moves about 1% from frame to frame.
    /// A keyframe with such a gain changed the water fit and lit a whole steady clip by 0.9 L (SnapInsta AQNT, 26 Oct 2026);
    /// the napoleon pulse needs 30 to 60%.
    static let deadBand: Float = 0.02
    /// Rec. 709 luminance.
    static let luminance = SIMD3<Float>(0.2126, 0.7152, 0.0722)
    /// Linear Rec. 709 to linear Rec. 2020 (ITU-R BT.2087).
    static let rec709To2020 = simd_float3x3(rows: [SIMD3(0.6274, 0.3293, 0.0433),
                                                  SIMD3(0.0691, 0.9195, 0.0114),
                                                  SIMD3(0.0164, 0.0880, 0.8956)])
    static let linear709 = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    /// Pixels the measured frame is shrunk to on its long side. The mean needs no more.
    static let measureDimension: CGFloat = 160

    /// The gains for frames at `times` with mean colours `means` (linear Rec. 709), in time order.
    static func make(times: [Double], means: [SIMD3<Float>]) -> VideoColourTrack? {
        guard times.count == means.count, times.count > 2 else { return nil }
        let shares = means.map { mean -> SIMD3<Float>? in
            let y = (mean * luminance).sum()
            guard y > 1e-5, mean.x.isFinite, mean.y.isFinite, mean.z.isFinite else { return nil }
            return mean / y
        }
        var gains: [SIMD3<Float>] = []
        gains.reserveCapacity(times.count)
        var low = 0, high = 0
        for index in times.indices {
            while times[low] < times[index] - window / 2 { low += 1 }
            while high + 1 < times.count && times[high + 1] <= times[index] + window / 2 { high += 1 }
            guard let share = shares[index] else { gains.append(SIMD3(repeating: 1)); continue }
            let around = shares[low...high].compactMap { $0 }
            func median(_ channel: Int) -> Float {
                let sorted = around.map { $0[channel] }.sorted()
                return sorted[sorted.count / 2]
            }
            let target = SIMD3(median(0), median(1), median(2))
            var gain = (target + floor) / (share + floor)
            // Same luminance after the gain.
            gain /= (share * gain * luminance).sum()
            gains.append(gain.x.isFinite && gain.y.isFinite && gain.z.isFinite ? gain : SIMD3(repeating: 1))
        }
        return VideoColourTrack(times: times, gains: gains)
    }

    /// The gain at `time`, linear between the two nearest frames.
    func gain(at time: Double) -> SIMD3<Float> {
        guard let first = times.first, let last = times.last else { return SIMD3(repeating: 1) }
        if time <= first { return gains[0] }
        if time >= last { return gains[gains.count - 1] }
        var low = 0, high = times.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if times[middle] <= time { low = middle } else { high = middle }
        }
        let span = times[high] - times[low]
        let t = span > 0 ? Float((time - times[low]) / span) : 0
        return gains[low] + (gains[high] - gains[low]) * t
    }

    /// The Rec. 709 gains at `time` as one matrix on the Rec. 2020 working space.
    func stabilised(_ image: CIImage, at time: Double) -> CIImage {
        // The band is taken off each gain, not used as a switch, so a gain that crosses it does not jump.
        let raw = gain(at: time) - 1
        let band = SIMD3(repeating: Self.deadBand)
        let g = 1 + raw - simd_clamp(raw, -band, band)
        guard g != SIMD3(repeating: 1) else { return image }
        let m = Self.rec709To2020 * simd_float3x3(diagonal: g) * Self.rec709To2020.inverse
        func row(_ i: Int) -> CIVector { CIVector(x: CGFloat(m[0][i]), y: CGFloat(m[1][i]), z: CGFloat(m[2][i]), w: 0) }
        return image.applyingFilter("CIColorMatrix", parameters: ["inputRVector": row(0), "inputGVector": row(1), "inputBVector": row(2)])
    }

    /// Reads every frame of the clip once, small, and measures its mean colour. `frame` maps a decoded
    /// frame as the analysis does (Apple Log decode, SDR). Without it (an SDR clip) the mean is taken on the CPU.
    /// Nil when the clip cannot be read this way: the video then keeps its frames as they are.
    /// @concurrent: a whole decode pass, so it runs off the caller's actor on purpose.
    @concurrent static func measure(url: URL, duration: Double, context: CIContext,
                        frame: (@Sendable (CIImage) -> CIImage)?) async throws -> VideoColourTrack? {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { return nil }
        let size = try await track.load(.naturalSize)
        let scale = min(1, measureDimension / max(1, max(abs(size.width), abs(size.height))))
        let width = max(2, Int((abs(size.width) * scale).rounded())), height = max(2, Int((abs(size.height) * scale).rounded()))
        let reader = try AVAssetReader(asset: asset)
        // The decoder's own 4:2:0 format for the CPU mean: BGRA cost 3x the decode time (26 Oct 2026, Mac: 0.68 s
        // against 0.25 s for 17 s of 1080p). Scaling in the reader saved nothing.
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: frame == nil
            ? [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
            : [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
               kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        defer { reader.cancelReading() }
        var times: [Double] = [], means: [SIMD3<Float>] = []
        var pixel = [Float](repeating: 0, count: 4)
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            guard time.isFinite, time <= duration, let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            if let frame {
                autoreleasepool {
                    let image = frame(CIImage(cvPixelBuffer: buffer))
                    let mean = image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: image.extent)])
                    context.render(mean, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                   format: .RGBAf, colorSpace: linear709)
                }
                means.append(SIMD3(pixel[0], pixel[1], pixel[2]))
            } else {
                guard let mean = mean(ycbcr: buffer) else { return nil }
                means.append(mean)
            }
            times.append(time)
        }
        guard reader.status == .completed else { return nil }
        // Frames come out in decode order on some clips; the window needs time order.
        let order = times.indices.sorted { times[$0] < times[$1] }
        return make(times: order.map { times[$0] }, means: order.map { means[$0] })
    }

    /// Rec. 709 signal (0 to 1) to linear light.
    private static func linear(_ v: Float) -> Float {
        let v = min(1, max(0, v))
        return v < 0.081 ? v / 4.5 : pow((v + 0.099) / 1.099, 1 / 0.45)
    }

    /// The mean linear Rec. 709 colour of a video-range 4:2:0 frame (420v, the decoder's own format), read on a
    /// grid of at most `measureDimension` px on the long side. A clip tagged BT.601 is converted with that matrix.
    static func mean(ycbcr buffer: CVPixelBuffer) -> SIMD3<Float>? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
              CVPixelBufferGetPlaneCount(buffer) == 2,
              CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let luma = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)?.assumingMemoryBound(to: UInt8.self),
              let chroma = CVPixelBufferGetBaseAddressOfPlane(buffer, 1)?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let lumaRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0), chromaRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
        let width = CVPixelBufferGetWidthOfPlane(buffer, 1), height = CVPixelBufferGetHeightOfPlane(buffer, 1)
        let matrix = CVBufferCopyAttachment(buffer, kCVImageBufferYCbCrMatrixKey, nil) as? String
        // (Cr to R, Cb to G, Cr to G, Cb to B)
        let k: SIMD4<Float> = matrix == (kCVImageBufferYCbCrMatrix_ITU_R_601_4 as String)
            ? SIMD4(1.402, 0.344136, 0.714136, 1.772) : SIMD4(1.5748, 0.1873, 0.4681, 1.8556)
        let step = max(1, 2 * max(width, height) / Int(measureDimension))
        var sum = SIMD3<Float>(repeating: 0), count: Float = 0
        for y in stride(from: 0, to: height, by: step) {
            let c = chroma + y * chromaRow, l = luma + 2 * y * lumaRow
            for x in stride(from: 0, to: width, by: step) {
                let yy = (Float(l[2 * x]) - 16) / 219
                let cb = (Float(c[2 * x]) - 128) / 224, cr = (Float(c[2 * x + 1]) - 128) / 224
                sum += SIMD3(linear(yy + k.x * cr), linear(yy - k.y * cb - k.z * cr), linear(yy + k.w * cb))
                count += 1
            }
        }
        return count > 0 ? sum / count : nil
    }
}
