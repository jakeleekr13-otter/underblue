import XCTest
import AVFoundation
import CoreImage
import VideoToolbox
@testable import UnderBlue

/// Apple Log support. Clips are written at run time (files under UnderBlueTests ship in the app bundle).
final class AppleLogTests: XCTestCase {
    /// Log signal of the patches: 0% black, 18% grey and 90% white (white paper table, page 4).
    static let patches: [Float] = [0.150477, 0.488272, 0.681686]

    func testCurveMatchesWhitePaperTable() {
        XCTAssertEqual(AppleLog.linear(0.150477), 0, accuracy: 0.0005)
        XCTAssertEqual(AppleLog.linear(0.488272), 0.18, accuracy: 0.0005)
        XCTAssertEqual(AppleLog.linear(0.681686), 0.90, accuracy: 0.001)
        XCTAssertEqual(AppleLog.linear(1), 12, accuracy: 0.01)
        XCTAssertEqual(AppleLog.linear(-0.1), -0.05641088, accuracy: 0.000001)
    }

    func testKernelDecodesAnSRGBTaggedSignal() throws {
        let engine = FilterEngine()
        let srgb = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        for p: Float in [0.3, 0.488272, 0.6, 0.681686] {
            let c = CGFloat(p)
            let signal = CIImage(color: try XCTUnwrap(CIColor(red: c, green: c, blue: c, colorSpace: srgb)))
                .cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
            let decoded = AppleLog.log.decode(signal)
            XCTAssertEqual(decoded.contentHeadroom, AppleLog.hlgHeadroom, accuracy: 0.001)
            var pixel = [Float](repeating: 0, count: 4)
            engine.context.render(decoded, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                  format: .RGBAf, colorSpace: FilterEngine.workingSpace)
            // Light up to 1.0 passes the highlight roll-off unchanged (measured 26 Oct 2026).
            for channel in 0..<3 { XCTAssertEqual(pixel[channel], AppleLog.linear(p), accuracy: 0.01, "P \(p)") }
        }
    }

    func testAppleWideGamutKeepsGreyAndDiffersFromRec2020() {
        let m = AppleLog.log2.toRec2020.transpose
        for row in [m.columns.0, m.columns.1, m.columns.2] { XCTAssertEqual(row.x + row.y + row.z, 1, accuracy: 0.000001) }
        XCTAssertGreaterThan(abs(m.columns.0.x - 1), 0.01)
        XCTAssertEqual(AppleLog.log.toRec2020, matrix_identity_double3x3)
    }

    func testProResRAWCodecsAreRecognised() {
        XCTAssertTrue(VideoMetadata.isProResRAW(kCMVideoCodecType_AppleProResRAW))
        XCTAssertTrue(VideoMetadata.isProResRAW(kCMVideoCodecType_AppleProResRAWHQ))
        XCTAssertFalse(VideoMetadata.isProResRAW(kCMVideoCodecType_AppleProRes422))
        XCTAssertEqual(Failure.classify(UnderBlueError.proResRAW, operation: .inspection).kind, .proResRAW)
    }

    func testLogClipsAreDetected() async throws {
        let url = try await Self.makeClip(.log)
        defer { TemporaryFiles.remove(url) }
        let metadata = try await MediaInspector().inspect(url)
        XCTAssertEqual(metadata.dynamicRange, .appleLog)
        XCTAssertNil(metadata.transfer)
        XCTAssertTrue(metadata.hdrExportable)
        XCTAssertEqual(metadata.hdrOutputRange, .hlg)
        let url2 = try await Self.makeClip(.log2)
        defer { TemporaryFiles.remove(url2) }
        let metadata2 = try await MediaInspector().inspect(url2)
        XCTAssertEqual(metadata2.dynamicRange, .appleLog2)
        XCTAssertNil(metadata2.primaries)
    }

    /// Flat log puts black at 0.15 and grey at 0.49. Decoded and tone mapped, black is 0 and grey about 0.39.
    func testSDRExportDecodesTheLog() async throws {
        for format in [AppleLog.log, .log2] {
            let url = try await Self.makeClip(format)
            defer { TemporaryFiles.remove(url) }
            let metadata = try await MediaInspector().inspect(url)
            let result = try await VideoExporter().export(url: url, metadata: metadata, settings: .init(preset: .original),
                                                          options: .init()) { _ in }
            defer { TemporaryFiles.remove(result.url) }
            XCTAssertEqual(result.metadata.transfer, AVVideoTransferFunction_ITU_R_709_2)
            let exported = AVURLAsset(url: result.url)
            let values = try await Self.patchValues(AVAssetReaderTrackOutput(
                track: try await exported.loadTracks(withMediaType: .video)[0],
                outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]), asset: exported)
            XCTAssertLessThan(values[0], 0.04, "\(format) black")
            XCTAssertEqual(values[1], 0.39, accuracy: 0.06, "\(format) grey")
            XCTAssertGreaterThan(values[2], values[1] + 0.2, "\(format) white")
        }
    }

    func testHDRExportOfLogIsHLGAndPassesValidation() async throws {
        let url = try await Self.makeClip(.log)
        defer { TemporaryFiles.remove(url) }
        let metadata = try await MediaInspector().inspect(url)
        let options = ExportOptions(range: .hdr)
        let result = try await VideoExporter().export(url: url, metadata: metadata, settings: .init(preset: .original),
                                                      options: options) { _ in }
        defer { TemporaryFiles.remove(result.url) }
        XCTAssertEqual(result.metadata.dynamicRange, .hlg)
        XCTAssertEqual(result.metadata.bitDepth, 10)
        _ = try await OutputValidator().validate(result.url, source: metadata, options: options, expectedFrames: result.frames)
    }

    func testPreviewOriginalShowsTheDecodedLog() async throws {
        let url = try await Self.makeClip(.log)
        defer { TemporaryFiles.remove(url) }
        let asset = AVURLAsset(url: url)
        let settings = PreviewSettings()
        settings.update(FilterSettings(preset: .original), comparing: true)
        let output = AVAssetReaderVideoCompositionOutput(videoTracks: try await asset.loadTracks(withMediaType: .video),
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.videoComposition = try await VideoPreview().composition(asset: asset, settings: settings)
        let values = try await Self.patchValues(output, asset: asset)
        // Flat log grey would read 0.49. The decode matches the export (linear 0.10), but the compositor
        // encodes Rec. 709 with gamma 1.961 where the export render uses 2.4, so grey reads 0.31 (26 Oct 2026).
        XCTAssertLessThan(values[0], 0.04, "black")
        XCTAssertEqual(values[1], 0.31, accuracy: 0.04, "grey")
    }

    // MARK: - Helpers

    /// A 4-frame 10-bit HEVC clip of three grey patches, tagged as Apple Log or Apple Log 2 the way
    /// AVVideoSettings.h says to write them.
    static func makeClip(_ format: AppleLog) async throws -> URL {
        let url = try TemporaryFiles.makeURL(extension: "mov")
        let width = 192, height = 64
        var colors: [String: Any] = [AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020]
        guard #available(iOS 27, *) else { throw XCTSkip("The log writer key needs iOS 27") }
        colors[AVVideoLogTransferFunctionKey] = format == .log ? AVVideoLogTransferFunction_AppleLog : AVVideoLogTransferFunction_AppleLog2
        if format == .log { colors[AVVideoColorPrimariesKey] = AVVideoColorPrimaries_ITU_R_2020 }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        // HEVC Main10, not ProRes: the simulator has no ProRes encoder ("Cannot Encode", 26 Oct 2026).
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width, AVVideoHeightKey: height, AVVideoColorPropertiesKey: colors,
            AVVideoCompressionPropertiesKey: [AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel,
                                              AVVideoAverageBitRateKey: 20_000_000]])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? UnderBlueError.exportFailed }
        writer.startSession(atSourceTime: .zero)
        for index in 0..<4 {
            var created: CVPixelBuffer?
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
                                [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &created)
            guard let buffer = created else { throw UnderBlueError.exportFailed }
            CVPixelBufferLockBaseAddress(buffer, [])
            let luma = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)!, lumaRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
            let chroma = CVPixelBufferGetBaseAddressOfPlane(buffer, 1)!, chromaRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
            for row in 0..<height {
                let line = (luma + row * lumaRow).assumingMemoryBound(to: UInt16.self)
                // Grey: Y' equals the signal; 10-bit video range, stored in the top bits.
                for x in 0..<width { line[x] = UInt16((64 + 876 * patches[x * 3 / width]).rounded()) << 6 }
            }
            for row in 0..<height / 2 {
                let line = (chroma + row * chromaRow).assumingMemoryBound(to: UInt16.self)
                for x in 0..<width { line[x] = 512 << 6 }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_2020, .shouldPropagate)
            CVBufferSetAttachment(buffer, kCVImageBufferLogTransferFunctionKey, format == .log
                ? kCVImageBufferLogTransferFunction_AppleLog : kCVImageBufferLogTransferFunction_AppleLog2, .shouldPropagate)
            if format == .log {
                CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_2020, .shouldPropagate)
            }
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 30)) else {
                throw writer.error ?? UnderBlueError.exportFailed
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? UnderBlueError.exportFailed }
        return url
    }

    /// The red channel, 0...1, at the centre of each patch in the first frame.
    static func patchValues(_ output: AVAssetReaderOutput, asset: AVAsset) async throws -> [Float] {
        let reader = try AVAssetReader(asset: asset)
        reader.add(output)
        guard reader.startReading(), let sample = output.copyNextSampleBuffer(),
              let buffer = CMSampleBufferGetImageBuffer(sample) else { throw reader.error ?? UnderBlueError.unreadable }
        defer { reader.cancelReading() }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let row = CVPixelBufferGetBaseAddress(buffer)! + (height / 2) * CVPixelBufferGetBytesPerRow(buffer)
        let pixels = row.assumingMemoryBound(to: UInt8.self)
        return (0..<3).map { Float(pixels[(width * (2 * $0 + 1) / 6) * 4 + 2]) / 255 }
    }
}
