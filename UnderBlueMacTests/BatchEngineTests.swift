import XCTest
import AVFoundation
import CoreImage
import ImageIO
@testable import UnderBlue

/// Moves each file into a folder like the real sink and remembers the order of arrival.
private actor RecordingSink: BatchSink {
    private(set) var names: [String] = []
    private let folder: DirectorySink
    init(directory: URL) { folder = DirectorySink(directory: directory) }
    func deliver(_ file: URL, fileName: String, kind: ImportedMedia.Kind) async throws -> String {
        let stored = try await folder.deliver(file, fileName: fileName, kind: kind)
        names.append(stored)
        return stored
    }
}

@MainActor
final class BatchEngineTests: XCTestCase {
    private var output: URL!
    private var created: [URL] = []

    override func setUp() async throws {
        output = FileManager.default.temporaryDirectory.appendingPathComponent("BatchEngineOut-\(UUID().uuidString)", isDirectory: true)
        created = [output]
    }
    override func tearDown() async throws { for url in created { try? FileManager.default.removeItem(at: url) } }

    private func makePhoto(_ color: CIColor, size: CGSize, name: String) throws -> ImportedMedia {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("BatchEngineSource-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        created.append(folder)
        let url = folder.appendingPathComponent(name)
        let image = CIImage(color: color).cropped(to: CGRect(origin: .zero, size: size))
        try FilterEngine().context.writeHEIFRepresentation(of: image, to: url, format: .RGBA8, colorSpace: FilterEngine.photoSpace)
        return ImportedMedia(url: url, kind: .photo, originalName: name)
    }

    private func video(_ name: String) throws -> ImportedMedia {
        // The clips are shared with the iOS tests and are read from the source tree.
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("UnderBlueTests/Fixtures/\(name)")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "missing fixture \(name)")
        return ImportedMedia(url: url, kind: .video, originalName: name)
    }

    private func engine(_ limits: BatchEngine.Limits = .init(), sink: BatchSink) -> BatchEngine {
        let diagnostics = DiagnosticRecorder(directory: FileManager.default.temporaryDirectory.appendingPathComponent("BatchEngineDiag-\(UUID().uuidString)"))
        return BatchEngine(limits: limits, sink: sink, diagnostics: diagnostics)
    }

    /// A slow 4K video comes first and two small photos follow, so the photos are ready long before the video.
    /// Delivery must still wait for the video. Two photos share one source name, so the second result needs a new name.
    private func mixedQueue() throws -> [ImportedMedia] {
        [try video("hevc_4k_24_audio.mov"),
         try makePhoto(CIColor(red: 0.10, green: 0.70, blue: 0.35), size: CGSize(width: 240, height: 160), name: "IMG_0001.heic"),
         try makePhoto(CIColor(red: 0.20, green: 0.50, blue: 0.60), size: CGSize(width: 240, height: 160), name: "IMG_0001.heic"),
         try video("h264_1080_30_audio.mov"),
         try makePhoto(CIColor(red: 0.05, green: 0.45, blue: 0.75), size: CGSize(width: 4000, height: 3000), name: "IMG_0002.heic")]
    }

    /// Each file starts from its own orientation. A turn set on one video applies to that video only; a photo refuses it.
    func testRotationIsPerVideoAndReachesTheExport() async throws {
        let sink = RecordingSink(directory: output)
        let batch = engine(sink: sink)
        batch.add([try video("portrait_audio.mov"), try video("portrait_audio.mov"),
                   try makePhoto(CIColor(red: 0.1, green: 0.5, blue: 0.6), size: CGSize(width: 240, height: 160), name: "IMG_0004.heic")])
        let ids = batch.items.map(\.id)
        XCTAssertTrue(batch.setRotation(ids[0], .quarter))
        XCTAssertFalse(batch.setRotation(ids[2], .quarter), "a photo has no turn")
        batch.start(settings: FilterSettings(preset: .original))
        XCTAssertFalse(batch.setRotation(ids[1], .half), "refused while running")
        await batch.waitUntilFinished()
        XCTAssertEqual(batch.items.map(\.state), [.done, .done, .done], batch.items.compactMap(\.error).joined(separator: "; "))
        XCTAssertFalse(batch.setRotation(ids[0], .half), "a saved video would not change")
        let names = await sink.names
        let turned = try await MediaInspector().inspect(output.appendingPathComponent(names[0]))
        let kept = try await MediaInspector().inspect(output.appendingPathComponent(names[1]))
        XCTAssertEqual(turned.displaySize, CGSize(width: 1920, height: 1080))
        XCTAssertEqual(kept.displaySize, CGSize(width: 1080, height: 1920))
    }

    /// A Pro run (`trial: false`, also the Mac app's path for Pro) has no mark. A free run has it in the bottom-right corner.
    func testProBatchHasNoWatermarkAndFreeBatchHasIt() async throws {
        let size = CGSize(width: 1200, height: 800)
        let mark = try XCTUnwrap(Watermark.mark(for: CGRect(origin: .zero, size: size))).extent.integral
        func run(trial: Bool) async throws -> CIImage {
            let folder = output.appendingPathComponent(trial ? "free" : "pro", isDirectory: true)
            let sink = RecordingSink(directory: folder)
            let batch = engine(sink: sink)
            batch.add([try makePhoto(CIColor(red: 0.15, green: 0.45, blue: 0.55), size: size, name: "IMG_0003.heic")])
            batch.start(settings: FilterSettings(), trial: trial)
            await batch.waitUntilFinished()
            XCTAssertEqual(batch.items.map(\.state), [.done], batch.items.compactMap(\.error).joined(separator: "; "))
            let names = await sink.names
            let name = try XCTUnwrap(names.first)
            return try XCTUnwrap(CIImage(contentsOf: folder.appendingPathComponent(name)))
        }
        let pro = try await run(trial: false), free = try await run(trial: true)
        XCTAssertEqual(pro.extent.size, size); XCTAssertEqual(free.extent.size, size)
        func pixels(_ image: CIImage) -> [Float] {
            var values = [Float](repeating: 0, count: Int(mark.width) * Int(mark.height) * 4)
            FilterEngine().context.render(image, toBitmap: &values, rowBytes: Int(mark.width) * 16, bounds: mark, format: .RGBAf,
                                          colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            return values
        }
        // The mark's own pixels sort the output's pixels into three groups: under its white parts, under its dark
        // icon fill, and where it is clear. Without a mark the three means match; the pipeline's slow light changes
        // do not follow the letter shapes.
        let shape = pixels(try XCTUnwrap(Watermark.mark(for: CGRect(origin: .zero, size: size))))
        func means(_ image: CIImage) -> (white: Float, dark: Float, clear: Float) {
            let values = pixels(image)
            var white: [Float] = [], dark: [Float] = [], clear: [Float] = []
            for index in stride(from: 0, to: values.count, by: 4) {
                let alpha = shape[index + 3], sum = values[index] + values[index + 1] + values[index + 2]
                let markSum = alpha > 0 ? (shape[index] + shape[index + 1] + shape[index + 2]) / alpha : 0
                if alpha > 0.8, markSum > 2.4 { white.append(sum) } else if alpha > 0.8, markSum < 0.6 { dark.append(sum) } else if alpha < 0.01 { clear.append(sum) }
            }
            XCTAssertGreaterThan(white.count, 50); XCTAssertGreaterThan(dark.count, 50); XCTAssertGreaterThan(clear.count, 50)
            let mean = { (group: [Float]) in group.reduce(0, +) / Float(max(1, group.count)) }
            return (mean(white), mean(dark), mean(clear))
        }
        let proMeans = means(pro), freeMeans = means(free)
        print("watermark group means (white, dark, clear): pro \(proMeans), free \(freeMeans)")
        XCTAssertEqual(proMeans.white, proMeans.clear, accuracy: 0.03, "Pro output brightens under the mark's letters")
        XCTAssertEqual(proMeans.dark, proMeans.clear, accuracy: 0.03, "Pro output darkens under the mark's icon")
        XCTAssertGreaterThan(freeMeans.white - freeMeans.clear, 0.5, "free output has no white letters")
        XCTAssertGreaterThan(freeMeans.clear - freeMeans.dark, 0.3, "free output has no dark icon")
    }

    /// Stage 3 artifact: 3 photos + 2 videos give 5 valid files, delivered in queue order.
    /// A video export already runs `OutputValidator` before it returns, so a finished video passed it.
    func testMixedBatchDeliversFiveValidFilesInQueueOrder() async throws {
        let sink = RecordingSink(directory: output)
        let batch = engine(.init(analysis: 1, videoExport: 1, photoExport: 3, inFlight: 5), sink: sink)
        let queue = try mixedQueue()
        batch.add(queue)
        batch.start(settings: FilterSettings())
        await batch.waitUntilFinished()

        XCTAssertEqual(batch.items.map(\.state), Array(repeating: .done, count: 5), batch.items.compactMap(\.error).joined(separator: "; "))
        let names = await sink.names
        let look = ExportNaming.token(FilterSettings().preset)
        let expected = ["hevc_4k_24_audio_UnderBlue_\(look)", "IMG_0001_UnderBlue_\(look)", "IMG_0001_UnderBlue_\(look)_2",
                        "h264_1080_30_audio_UnderBlue_\(look)", "IMG_0002_UnderBlue_\(look)"]
        XCTAssertEqual(names.count, 5)
        XCTAssertEqual(Set(names).count, 5, "every result has its own name")
        for (name, stem) in zip(names, expected) {
            XCTAssertEqual((name as NSString).deletingPathExtension, stem, "queue order and names")
        }

        // Every file exists, opens, and keeps the source size or duration.
        let files = try FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 5)
        for (index, media) in queue.enumerated() {
            let file = output.appendingPathComponent(names[index])
            switch media.kind {
            case .photo:
                let source = try XCTUnwrap(CGImageSourceCreateWithURL(file as CFURL, nil))
                let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
                let original = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(try XCTUnwrap(CGImageSourceCreateWithURL(media.url as CFURL, nil)), 0, nil) as? [CFString: Any])
                XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, original[kCGImagePropertyPixelWidth] as? Int, names[index])
                XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, original[kCGImagePropertyPixelHeight] as? Int, names[index])
            case .video:
                let result = try await MediaInspector().inspect(file)
                let source = try await MediaInspector().inspect(media.url)
                XCTAssertTrue(["hvc1", "hev1"].contains(result.codec), names[index])
                XCTAssertEqual(result.duration, source.duration, accuracy: 0.2, names[index])
                XCTAssertEqual(result.audioTrackCount, source.audioTrackCount, names[index])
            }
        }
    }

    /// A cancel keeps finished items and stops the rest. `start()` again finishes the rest and leaves the finished ones alone.
    func testCancelThenResumeFinishesTheRest() async throws {
        let sink = RecordingSink(directory: output)
        let batch = engine(sink: sink)
        batch.add(try mixedQueue())
        batch.start(settings: FilterSettings())
        // Cancel as soon as the first result is delivered.
        while batch.doneCount == 0 && batch.running { try await Task.sleep(for: .milliseconds(20)) }
        batch.cancel()
        await batch.waitUntilFinished()
        let doneBefore = batch.doneCount
        XCTAssertGreaterThanOrEqual(doneBefore, 1)
        XCTAssertLessThan(doneBefore, 5, "the cancel stopped the run before the end")
        XCTAssertTrue(batch.items.allSatisfy { [.done, .cancelled].contains($0.state) }, "\(batch.items.map(\.state))")

        batch.start(settings: FilterSettings())
        await batch.waitUntilFinished()
        XCTAssertEqual(batch.items.map(\.state), Array(repeating: .done, count: 5), batch.items.compactMap(\.error).joined(separator: "; "))
        let names = await sink.names
        XCTAssertEqual(names.count, 5, "a finished item is not run twice")
        XCTAssertEqual(Set(names).count, 5)
        let leftovers = try FileManager.default.contentsOfDirectory(at: TemporaryFiles.directory, includingPropertiesForKeys: nil)
        XCTAssertTrue(leftovers.isEmpty, "no temporary result files are left: \(leftovers.map(\.lastPathComponent))")
    }

    /// One bad file fails alone. The others finish, and a retry run picks it up.
    func testBadFileFailsAloneAndTheOthersFinish() async throws {
        let sink = RecordingSink(directory: output)
        let batch = engine(sink: sink)
        let bad = FileManager.default.temporaryDirectory.appendingPathComponent("not-a-photo-\(UUID().uuidString).heic")
        try Data("not an image".utf8).write(to: bad)
        created.append(bad)
        batch.add([try makePhoto(CIColor(red: 0.1, green: 0.5, blue: 0.7), size: CGSize(width: 240, height: 160), name: "a.heic"),
                   ImportedMedia(url: bad, kind: .photo, originalName: "bad.heic"),
                   try makePhoto(CIColor(red: 0.1, green: 0.6, blue: 0.3), size: CGSize(width: 240, height: 160), name: "c.heic")])
        batch.start(settings: FilterSettings())
        await batch.waitUntilFinished()
        XCTAssertEqual(batch.items.map(\.state), [.done, .failed, .done])
        XCTAssertNotNil(batch.items[1].error)
        let names = await sink.names
        XCTAssertEqual(names.count, 2)
    }

    func testSubjectChoiceIsPerItemAndRefusedWhileRunning() throws {
        let queue = engine(sink: DirectorySink(directory: output))
        queue.add([try makePhoto(CIColor(red: 0.1, green: 0.5, blue: 0.7), size: CGSize(width: 64, height: 48), name: "A.heic"),
                   try makePhoto(CIColor(red: 0.1, green: 0.5, blue: 0.7), size: CGSize(width: 64, height: 48), name: "B.heic")])
        let picked = SubjectChoice.picked(SubjectMask(width: 2, height: 2, values: [1, 0, 0, 0]))
        XCTAssertTrue(queue.setSubjects(queue.items[0].id, picked))
        XCTAssertEqual(queue.items[0].subjects, picked)
        XCTAssertEqual(queue.items[1].subjects, .off, "only the picked item changes")
        XCTAssertFalse(queue.setSubjects(UUID(), picked), "an unknown item is refused")
    }

    /// The Mac app checks the free trial against the queued items, then awaits before the run starts. A file added
    /// in that gap must wait for the next run, so a free run stays one file (flow review 6.2, 4 Nov 2026).
    func testStartOnlyRunsTheGivenItems() async throws {
        let sink = RecordingSink(directory: output)
        let batch = engine(sink: sink)
        let color = CIColor(red: 0.15, green: 0.45, blue: 0.55), size = CGSize(width: 240, height: 160)
        batch.add([try makePhoto(color, size: size, name: "IMG_0010.heic"), try makePhoto(color, size: size, name: "IMG_0011.heic")])
        let first = try XCTUnwrap(batch.items.first?.id)
        batch.start(settings: FilterSettings(), trial: true, only: [first])
        await batch.waitUntilFinished()
        XCTAssertEqual(batch.items.map(\.state), [.done, .queued], batch.items.compactMap(\.error).joined(separator: "; "))
        let names = await sink.names
        XCTAssertEqual(names.count, 1)
    }
    func testUniqueNameAddsANumberUntilFree() {
        let taken: Set = ["a.jpg", "a_2.jpg", "a_3.jpg"]
        XCTAssertEqual(ExportNaming.unique("b.jpg") { taken.contains($0) }, "b.jpg")
        XCTAssertEqual(ExportNaming.unique("a.jpg") { taken.contains($0) }, "a_4.jpg")
        XCTAssertEqual(ExportNaming.unique("a") { taken.contains($0) }, "a")
    }
}
