import XCTest
import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
@testable import UnderBlue

/// Free exports carry the mark in the bottom-right corner; other pixels and Pro exports stay as they were.
final class WatermarkTests: XCTestCase {
    private let context = CIContext(options: [.cacheIntermediates: false])
    /// Kept alive while their outputs are read.
    private var readers: [AVAssetReader] = []

    /// Mean absolute RGB difference of two images inside `rect` (Core Image coordinates, origin bottom left).
    private func difference(_ a: CIImage, _ b: CIImage, in rect: CGRect) -> Float {
        func pixels(_ image: CIImage) -> [Float] {
            var values = [Float](repeating: 0, count: Int(rect.width) * Int(rect.height) * 4)
            context.render(image, toBitmap: &values, rowBytes: Int(rect.width) * 16, bounds: rect, format: .RGBAf,
                           colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            return values
        }
        let x = pixels(a), y = pixels(b)
        var sum: Float = 0
        for index in stride(from: 0, to: x.count, by: 4) {
            sum += abs(x[index] - y[index]) + abs(x[index + 1] - y[index + 1]) + abs(x[index + 2] - y[index + 2])
        }
        return sum / Float(x.count / 4 * 3)
    }
    private func water(_ size: CGSize) -> CIImage {
        CIImage(color: CIColor(red: 0.15, green: 0.45, blue: 0.55)).cropped(to: CGRect(origin: .zero, size: size))
    }

    /// The mark's own area (with its shadow padding) for an image of this size.
    private func markRect(_ size: CGSize) throws -> CGRect {
        try XCTUnwrap(Watermark.mark(for: CGRect(origin: .zero, size: size))).extent.integral
    }
    func testMarkSitsInTheBottomRightAndKeepsTheExtent() throws {
        let size = CGSize(width: 1200, height: 800)
        let source = water(size), marked = Watermark.apply(to: source), mark = try markRect(size)
        XCTAssertEqual(marked.extent, source.extent)
        // 32 px icon, 24 px from the right and bottom edges (4% and 3% of the 800 px short side).
        XCTAssertGreaterThan(mark.minX, 900); XCTAssertLessThan(mark.maxX, 1200); XCTAssertLessThan(mark.maxY, 80)
        XCTAssertGreaterThan(difference(source, marked, in: mark), 0.03)
        XCTAssertEqual(difference(source, marked, in: CGRect(x: 0, y: mark.maxY, width: 1200, height: 800 - mark.maxY)), 0, accuracy: 0.0001)
        XCTAssertEqual(difference(source, marked, in: CGRect(x: 0, y: 0, width: mark.minX, height: mark.maxY)), 0, accuracy: 0.0001)
    }
    /// The editor and the batch both decide through `applyTrial`. Pro must never get the mark, also after a free export.
    func testOnlyFreeExportsGetTheMark() {
        var options = ExportOptions(resolution: .source, range: .hdr)
        options.applyTrial(false)
        XCTAssertFalse(options.watermark); XCTAssertNil(options.durationLimit)
        XCTAssertEqual(options.resolution, .source); XCTAssertEqual(options.range, .hdr)
        options.applyTrial(true)
        XCTAssertTrue(options.watermark); XCTAssertEqual(options.durationLimit, 10)
        XCTAssertEqual(options.resolution, .hd); XCTAssertEqual(options.range, .sdr)
        options.applyTrial(false)
        XCTAssertFalse(options.watermark); XCTAssertNil(options.durationLimit)
    }
    func testTinyImageIsLeftAlone() {
        let source = water(CGSize(width: 60, height: 40))
        XCTAssertEqual(difference(source, Watermark.apply(to: source), in: source.extent), 0)
    }
    func testPhotoExportCarriesTheMarkOnlyWhenAsked() async throws {
        let url = try TemporaryFiles.makeURL(extension: "jpg")
        defer { TemporaryFiles.remove(url) }
        let source = water(CGSize(width: 1200, height: 800))
        let cg = try XCTUnwrap(context.createCGImage(source, from: source.extent, format: .RGBA8, colorSpace: FilterEngine.photoSpace))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, cg, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let processor = PhotoProcessor()
        let plain = try await processor.export(url, settings: .init())
        let marked = try await processor.export(url, settings: .init(), watermark: true)
        defer { TemporaryFiles.remove(plain); TemporaryFiles.remove(marked) }
        let a = try XCTUnwrap(CIImage(contentsOf: plain)), b = try XCTUnwrap(CIImage(contentsOf: marked))
        XCTAssertEqual(b.extent.size, CGSize(width: 1200, height: 800))
        XCTAssertGreaterThan(difference(a, b, in: try markRect(b.extent.size)), 0.03)
        XCTAssertLessThan(difference(a, b, in: CGRect(x: 0, y: 400, width: 600, height: 400)), 0.002)
    }
    func testTrialVideoCarriesTheMarkOnEveryFrame() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "h264_1080_30_audio", withExtension: "mov"))
        let metadata = try await MediaInspector().inspect(url)
        var options = ExportOptions(resolution: .hd, durationLimit: 2)
        let plain = try await VideoExporter().export(url: url, metadata: metadata, settings: .init(preset: .original), options: options) { _ in }
        options.watermark = true
        let marked = try await VideoExporter().export(url: url, metadata: metadata, settings: .init(preset: .original), options: options) { _ in }
        defer { TemporaryFiles.remove(plain.url); TemporaryFiles.remove(marked.url) }
        func frames(_ url: URL) async throws -> AVAssetReaderTrackOutput {
            let asset = AVURLAsset(url: url)
            let track = try await asset.loadTracks(withMediaType: .video).first
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: try XCTUnwrap(track),
                                                  outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            reader.add(output)
            XCTAssertTrue(reader.startReading())
            readers.append(reader)
            return output
        }
        let a = try await frames(plain.url), b = try await frames(marked.url)
        let mark = try markRect(CGSize(width: 1920, height: 1080))
        var count = 0
        while let left = a.copyNextSampleBuffer().flatMap(CMSampleBufferGetImageBuffer),
              let right = b.copyNextSampleBuffer().flatMap(CMSampleBufferGetImageBuffer) {
            let x = CIImage(cvPixelBuffer: left), y = CIImage(cvPixelBuffer: right)
            XCTAssertEqual(y.extent.size, CGSize(width: 1920, height: 1080))
            XCTAssertGreaterThan(difference(x, y, in: mark), 0.03, "frame \(count)")
            XCTAssertLessThan(difference(x, y, in: CGRect(x: 0, y: 540, width: 960, height: 540)), 0.01, "frame \(count)")
            count += 1
        }
        XCTAssertEqual(count, marked.frames)
    }
}
