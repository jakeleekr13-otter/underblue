import AVFoundation
import CoreImage

/// A turn the user adds on top of the file's own orientation, clockwise as seen on screen.
/// The file's orientation is always applied first. A wrong or missing tag can then be fixed by hand.
enum VideoRotation: Int, CaseIterable, Sendable, Hashable {
    case none = 0, quarter = 90, half = 180, threeQuarters = 270

    /// The next turn of 90° clockwise. After 270° it goes back to none.
    var next: VideoRotation { VideoRotation(rawValue: (rawValue + 90) % 360) ?? .none }
    var swapsSides: Bool { self == .quarter || self == .threeQuarters }
    /// The size after the turn. A turn of 90° or 270° swaps width and height.
    func applied(to size: CGSize) -> CGSize { swapsSides ? CGSize(width: size.height, height: size.width) : size }
    /// Turns the image clockwise on screen and moves it back to the origin.
    /// Core Image is y-up, so these are exact matrices, not a rotation angle with rounding.
    func apply(_ image: CIImage) -> CIImage {
        let turn: CGAffineTransform = switch self {
        case .none: .identity
        case .quarter: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 0)
        case .half: CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 0, ty: 0)
        case .threeQuarters: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: 0)
        }
        guard self != .none else { return image }
        let turned = image.transformed(by: turn)
        return turned.transformed(by: CGAffineTransform(translationX: -turned.extent.minX, y: -turned.extent.minY))
    }
}

struct VideoMetadata: Sendable {
    enum DynamicRange: String, Sendable {
        case sdr = "SDR", hlg = "HLG", pq = "HDR10", unknownHDR = "HDR", appleLog = "Apple Log", appleLog2 = "Apple Log 2"
    }
    let codec: String
    let codedSize: CGSize
    let displaySize: CGSize
    let transform: CGAffineTransform
    let duration: Double
    let frameRate: Float
    let bitDepth: Int?
    let primaries: String?
    let transfer: String?
    let matrix: String?
    let dynamicRange: DynamicRange
    let hasDolbyVisionSignaling: Bool
    let audioTrackCount: Int
    /// End of the video track in seconds. The asset duration covers every track, so a longer audio
    /// track can run past the last video frame. Frame reads must stay before this time.
    var videoEnd: Double? = nil
    /// The average bitrate of the video track in bits per second (`estimatedDataRate`: track bytes over its length,
    /// so a variable-bitrate source gives its average). Nil when unknown. The export bitrate never goes above it.
    var videoBitRate: Double? = nil
    /// `transform` for a CIImage. The track transform uses a y-down space; Core Image is y-up.
    /// Used as is, a 90° turn goes the wrong way and the frame comes out upside down (GX017598.MP4, 13 Nov 2026).
    /// Only the linear part is kept: callers move the result back to the origin.
    var ciTransform: CGAffineTransform {
        CGAffineTransform(a: transform.a, b: -transform.b, c: -transform.c, d: transform.d, tx: 0, ty: 0)
    }
    var isHDR: Bool { dynamicRange != .sdr }
    var appleLog: AppleLog? { AppleLog(dynamicRange) }
    /// HDR export needs a known source curve and 10 bits: HLG, PQ or Apple Log.
    var hdrExportable: Bool { [.hlg, .pq, .appleLog, .appleLog2].contains(dynamicRange) && (bitDepth ?? 0) >= 10 }
    /// HDR export keeps PQ as PQ. HLG and Apple Log export as HLG.
    var hdrOutputRange: DynamicRange { dynamicRange == .pq ? .pq : .hlg }
    /// ProRes RAW needs a RAW conversion. iOS has none, so the iPhone app refuses it. On the Mac the decoder
    /// runs Apple's RAW processing with default settings and hands out normal frames
    /// (VTDecompressionProperties.h, kVTDecompressionPropertyKey_RequestRAWOutput). Not yet checked on a real file.
    static func isProResRAW(_ subtype: FourCharCode) -> Bool {
        subtype == kCMVideoCodecType_AppleProResRAW || subtype == kCMVideoCodecType_AppleProResRAWHQ
    }
    /// The span that has video frames: the asset duration, cut at the video track's end.
    var videoDuration: Double { min(duration, videoEnd.map { $0 > 0 ? $0 : duration } ?? duration) }
}
struct MediaInspector {
    func inspect(_ url: URL) async throws -> VideoMetadata {
        let asset = AVURLAsset(url: url)
        let readable = try await asset.load(.isReadable)
        let firstTrack = try? await asset.loadTracks(withMediaType: .video).first
        #if os(iOS)
        if let firstTrack, try await firstTrack.load(.formatDescriptions).contains(where: { VideoMetadata.isProResRAW(CMFormatDescriptionGetMediaSubType($0)) }) {
            throw UnderBlueError.proResRAW
        }
        #endif
        guard readable, let track = firstTrack else { throw UnderBlueError.unreadable }
        let (size, transform, rate, formats, range) = try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate, .formatDescriptions, .timeRange)
        guard let format = formats.first else { throw UnderBlueError.unsupported }
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0, size.width > 0, size.height > 0 else { throw UnderBlueError.unreadable }
        let extensions = (CMFormatDescriptionGetExtensions(format) as NSDictionary?) ?? [:]
        let transfer = extensions[kCMFormatDescriptionExtension_TransferFunction] as? String
        let primaries = extensions[kCMFormatDescriptionExtension_ColorPrimaries] as? String
        let matrix = extensions[kCMFormatDescriptionExtension_YCbCrMatrix] as? String
        let atoms = extensions[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms] as? [String: Any] ?? [:]
        var depth = (extensions[kCMFormatDescriptionExtension_BitsPerComponent] as? NSNumber)?.intValue
        // HEVCDecoderConfigurationRecord contains explicit luma depth; absent metadata stays unknown.
        if depth == nil, let hvcc = atoms["hvcC"] as? Data, hvcc.count > 18 { depth = 8 + Int(hvcc[17] & 7) }
        let subtype = CMFormatDescriptionGetMediaSubType(format)
        let bytes = [UInt8((subtype >> 24) & 255), UInt8((subtype >> 16) & 255), UInt8((subtype >> 8) & 255), UInt8(subtype & 255)]
        let codec = String(bytes: bytes, encoding: .ascii) ?? "Unknown"
        let dynamicRange: VideoMetadata.DynamicRange
        // Apple Log files carry no transfer function; the log key names the curve.
        let log = AppleLog(identifier: extensions[kCMFormatDescriptionExtension_LogTransferFunction] as? String)
        if log == .log { dynamicRange = .appleLog }
        else if log == .log2 { dynamicRange = .appleLog2 }
        else if transfer == AVVideoTransferFunction_ITU_R_2100_HLG { dynamicRange = .hlg }
        else if transfer == AVVideoTransferFunction_SMPTE_ST_2084_PQ { dynamicRange = .pq }
        else if try await track.load(.mediaCharacteristics).contains(.containsHDRVideo) { dynamicRange = .unknownHDR }
        else { dynamicRange = .sdr }
        let videoEnd = range.end.seconds
        let dataRate = Double((try? await track.load(.estimatedDataRate)) ?? 0)
        let rect = CGRect(origin: .zero, size: size).applying(transform).standardized
        return VideoMetadata(codec: codec, codedSize: size, displaySize: rect.size, transform: transform,
            duration: duration, frameRate: rate, bitDepth: depth, primaries: primaries, transfer: transfer, matrix: matrix,
            dynamicRange: dynamicRange, hasDolbyVisionSignaling: atoms["dvcC"] != nil || atoms["dvvC"] != nil || codec == "dvh1" || codec == "dvhe",
            audioTrackCount: try await asset.loadTracks(withMediaType: .audio).count,
            videoEnd: videoEnd.isFinite && videoEnd > 0 ? videoEnd : nil,
            videoBitRate: dataRate.isFinite && dataRate > 0 ? dataRate : nil)
    }
}
