import AVFoundation
import CoreImage
import VideoToolbox

// Reader and writer explicitly agree on transfer function, gamut and bit depth.
// For SDR, AVFoundation tone maps HDR while decoding, before quantizing to 8-bit.
enum VideoColorPipeline {
    static func properties(hdr: Bool, pq: Bool = false) -> [String: Any] {
        [AVVideoColorPrimariesKey: hdr ? AVVideoColorPrimaries_ITU_R_2020 : AVVideoColorPrimaries_ITU_R_709_2,
         AVVideoTransferFunctionKey: hdr ? (pq ? AVVideoTransferFunction_SMPTE_ST_2084_PQ : AVVideoTransferFunction_ITU_R_2100_HLG) : AVVideoTransferFunction_ITU_R_709_2,
         AVVideoYCbCrMatrixKey: hdr ? AVVideoYCbCrMatrix_ITU_R_2020 : AVVideoYCbCrMatrix_ITU_R_709_2]
    }
    /// The colour space a frame is rendered into. SDR takes the space CoreVideo reads the Rec. 709 tags as. Core Image
    /// decodes the source with it (gamma 1.961), and the preview compositor encodes with it. CGColorSpace.itur_709
    /// encodes with 2.4, so the SDR export came out brighter than its source and the preview: grey 0.50 -> 0.56, even
    /// with the Original preset (30 Oct 2026).
    static func colorSpace(hdr: Bool, pq: Bool = false) -> CGColorSpace {
        hdr ? CGColorSpace(name: pq ? CGColorSpace.itur_2100_PQ : CGColorSpace.itur_2100_HLG)! : sdrSpace
    }
    private static let sdrSpace: CGColorSpace = {
        let tags = [kCVImageBufferColorPrimariesKey: kCVImageBufferColorPrimaries_ITU_R_709_2,
                    kCVImageBufferTransferFunctionKey: kCVImageBufferTransferFunction_ITU_R_709_2,
                    kCVImageBufferYCbCrMatrixKey: kCVImageBufferYCbCrMatrix_ITU_R_709_2] as CFDictionary
        return CVImageBufferCreateColorSpaceFromAttachments(tags)?.takeRetainedValue() ?? CGColorSpace(name: CGColorSpace.itur_709)!
    }()
    static func compression(hdr: Bool, bitrate: Int, frameRate: Float) -> [String: Any] {
        var settings: [String: Any] = [AVVideoAverageBitRateKey: bitrate,
            AVVideoExpectedSourceFrameRateKey: frameRate, AVVideoAllowFrameReorderingKey: false,
            kVTCompressionPropertyKey_HDRMetadataInsertionMode as String: kVTHDRMetadataInsertionMode_None,
            kVTCompressionPropertyKey_PreserveDynamicHDRMetadata as String: false]
        if hdr { settings[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main10_AutoLevel }
        return settings
    }
    static func tag(_ buffer: CVPixelBuffer, hdr: Bool, pq: Bool = false) {
        let values: [(CFString, CFString)] = [
            (kCVImageBufferColorPrimariesKey, hdr ? kCVImageBufferColorPrimaries_ITU_R_2020 : kCVImageBufferColorPrimaries_ITU_R_709_2),
            (kCVImageBufferTransferFunctionKey, hdr ? (pq ? kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ : kCVImageBufferTransferFunction_ITU_R_2100_HLG) : kCVImageBufferTransferFunction_ITU_R_709_2),
            (kCVImageBufferYCbCrMatrixKey, hdr ? kCVImageBufferYCbCrMatrix_ITU_R_2020 : kCVImageBufferYCbCrMatrix_ITU_R_709_2)]
        for (key, value) in values { CVBufferSetAttachment(buffer, key, value, .shouldPropagate) }
    }
}

struct ExportCapability: Sendable {
    let hdrAvailable: Bool
    let explanation: String
    static var photo: Self { Self(hdrAvailable: false, explanation: String(localized: "HDR photo export is unavailable. Your photo will be saved in SDR with wide color.")) }
    static func evaluate(url: URL, metadata: VideoMetadata) async -> Self {
        guard metadata.isHDR else { return Self(hdrAvailable: false, explanation: String(localized: "This video is SDR. HDR export requires HDR source footage.")) }
        guard metadata.hdrExportable else {
            return Self(hdrAvailable: false, explanation: String(localized: "This video’s HDR format cannot be safely exported as HDR."))
        }
        #if targetEnvironment(simulator)
        return Self(hdrAvailable: false, explanation: String(localized: "HDR export requires a supported iPhone. SDR export is available in the simulator."))
        #else
        // Test the actual source, decoder, Core Image path and encoder at source resolution.
        // No entitlement is consumed. Failure conservatively leaves HDR unavailable.
        do {
            var options = ExportOptions()
            options.range = .hdr; options.durationLimit = min(0.2, metadata.duration)
            let result = try await VideoExporter().export(url: url, metadata: metadata, settings: .init(preset: .original), options: options) { _ in }
            TemporaryFiles.remove(result.url)
            return Self(hdrAvailable: true, explanation: String(localized: "HDR · HEVC · 10-bit. The editor shows a tone-mapped SDR preview."))
        } catch {
            return Self(hdrAvailable: false, explanation: String(localized: "HDR export is unavailable for this media/device. You can export SDR."))
        }
        #endif
    }
}
