import XCTest
import AVFoundation
import CoreImage
@testable import UnderBlue

/// The preview and the export must show the same frame alike (Jake, 30 Oct 2026). Before, the preview
/// compositor encoded Rec. 709 with gamma 1.961 and the export render with 2.4.
final class VideoPreviewExportMatchTests: XCTestCase {
    /// Code values (sRGB-style 0...1) of three patches: blue water, mid grey, a warm subject.
    static let patches: [SIMD3<Float>] = [SIMD3(0.12, 0.35, 0.55), SIMD3(0.5, 0.5, 0.5), SIMD3(0.62, 0.45, 0.3)]

    func testPreviewAndExportRenderTheSameFrame() async throws {
        let url = try await Self.makeClip()
        defer { TemporaryFiles.remove(url) }
        let asset = AVURLAsset(url: url)
        let metadata = try await MediaInspector().inspect(url)
        for preset in [DivePreset.original, .natural] {
            let filter = FilterSettings(preset: preset)
            let settings = PreviewSettings()
            settings.update(filter, comparing: false)
            let preview = AVAssetReaderVideoCompositionOutput(videoTracks: try await asset.loadTracks(withMediaType: .video),
                videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            preview.videoComposition = try await VideoPreview().composition(asset: asset, settings: settings)
            let shown = try await Self.patchColours(preview, asset: asset)

            let result = try await VideoExporter().export(url: url, metadata: metadata, settings: filter,
                                                          options: ExportOptions()) { _ in }
            defer { TemporaryFiles.remove(result.url) }
            let exported = AVURLAsset(url: result.url)
            let tracks = try await exported.loadTracks(withMediaType: .video)
            let track = try XCTUnwrap(tracks.first)
            let saved = try await Self.patchColours(AVAssetReaderTrackOutput(track: track, outputSettings:
                [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]), asset: exported)
            for (index, (a, b)) in zip(shown, saved).enumerated() {
                for channel in 0..<3 {
                    XCTAssertEqual(a[channel], b[channel], accuracy: 0.03, "\(preset) patch \(index) channel \(channel)")
                }
            }
        }
    }

    /// A 4-frame 8-bit H.264 clip of the three patches, tagged Rec. 709.
    static func makeClip() async throws -> URL {
        let url = try TemporaryFiles.makeURL(extension: "mov")
        let width = 192, height = 64
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 20_000_000]])
        let receiver = writer.inputPixelBufferReceiver(for: input, pixelBufferAttributes: nil)
        try writer.start()
        writer.startSession(atSourceTime: .zero)
        for index in 0..<4 {
            let frame = try CVMutablePixelBuffer(try XCTUnwrap(CVPixelBufferCreationAttributes(CVPixelBufferAttributes(rawAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Int]()]))))
            frame.withUnsafeBuffer { buffer in
                CVPixelBufferLockBaseAddress(buffer, [])
                let base = CVPixelBufferGetBaseAddress(buffer)!, row = CVPixelBufferGetBytesPerRow(buffer)
                for y in 0..<height {
                    let line = (base + y * row).assumingMemoryBound(to: UInt8.self)
                    for x in 0..<width {
                        let c = patches[x * 3 / width]
                        line[x * 4] = UInt8(c.z * 255); line[x * 4 + 1] = UInt8(c.y * 255)
                        line[x * 4 + 2] = UInt8(c.x * 255); line[x * 4 + 3] = 255
                    }
                }
                CVPixelBufferUnlockBaseAddress(buffer, [])
                CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
                CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
                CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
            }
            try await receiver.append(CVReadOnlyPixelBuffer(frame), with: CMTime(value: CMTimeValue(index), timescale: 30))
        }
        receiver.finish()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? UnderBlueError.exportFailed }
        return url
    }

    /// The colour, 0...1, at the centre of each patch in the first frame.
    static func patchColours(_ output: AVAssetReaderOutput, asset: AVAsset) async throws -> [SIMD3<Float>] {
        let reader = try AVAssetReader(asset: asset)
        let frames = reader.outputProvider(for: output)
        try reader.start()
        defer { reader.cancelReading() }
        guard let sample = try await frames.next() else { throw reader.error ?? UnderBlueError.unreadable }
        let values: [SIMD3<Float>]? = sample.withUnsafeSampleBuffer { sampleBuffer in
            guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
            let pixels = (CVPixelBufferGetBaseAddress(buffer)! + (height / 2) * CVPixelBufferGetBytesPerRow(buffer))
                .assumingMemoryBound(to: UInt8.self)
            return (0..<3).map { patch in
                let x = (width * (2 * patch + 1) / 6) * 4
                return SIMD3(Float(pixels[x + 2]), Float(pixels[x + 1]), Float(pixels[x])) / 255
            }
        }
        guard let values else { throw UnderBlueError.unreadable }
        return values
    }
}
