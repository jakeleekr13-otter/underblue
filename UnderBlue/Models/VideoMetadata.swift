import AVFoundation

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
        let rect = CGRect(origin: .zero, size: size).applying(transform).standardized
        return VideoMetadata(codec: codec, codedSize: size, displaySize: rect.size, transform: transform,
            duration: duration, frameRate: rate, bitDepth: depth, primaries: primaries, transfer: transfer, matrix: matrix,
            dynamicRange: dynamicRange, hasDolbyVisionSignaling: atoms["dvcC"] != nil || atoms["dvvC"] != nil || codec == "dvh1" || codec == "dvhe",
            audioTrackCount: try await asset.loadTracks(withMediaType: .audio).count,
            videoEnd: videoEnd.isFinite && videoEnd > 0 ? videoEnd : nil)
    }
}
