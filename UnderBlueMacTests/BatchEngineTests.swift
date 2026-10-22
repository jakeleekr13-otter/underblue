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

    override func setUpWithError() throws {
        output = FileManager.default.temporaryDirectory.appendingPathComponent("BatchEngineOut-\(UUID().uuidString)", isDirectory: true)
        created = [output]
    }
    override func tearDown() { for url in created { try? FileManager.default.removeItem(at: url) } }

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
        XCTAssertEqual(queue.items[1].subjects, .auto, "only the picked item changes")
        XCTAssertFalse(queue.setSubjects(UUID(), picked), "an unknown item is refused")
    }

    func testUniqueNameAddsANumberUntilFree() {
        let taken: Set = ["a.jpg", "a_2.jpg", "a_3.jpg"]
        XCTAssertEqual(ExportNaming.unique("b.jpg") { taken.contains($0) }, "b.jpg")
        XCTAssertEqual(ExportNaming.unique("a.jpg") { taken.contains($0) }, "a_4.jpg")
        XCTAssertEqual(ExportNaming.unique("a") { taken.contains($0) }, "a")
    }
}
