import XCTest
import UniformTypeIdentifiers
@testable import UnderBlue

/// The share path without Finder: the extension's copy step (ShareModel), then the app's import step (MacModel.importShared).
/// The real share menu needs a signed build and cannot run here.
@MainActor
final class ShareFlowTests: XCTestCase {
    private static var alive: [MacModel] = []
    private var folders: [URL] = []

    override func tearDown() async throws { for folder in folders { try? FileManager.default.removeItem(at: folder) } }

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ShareFlow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        folders.append(folder)
        return folder
    }

    private func makeFile(_ name: String, in folder: URL, bytes: String) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data(bytes.utf8).write(to: url)
        return url
    }

    /// A provider the way the share menu hands it over: a file, and the file's name without extension as the suggested name.
    private func provider(for file: URL) -> NSItemProvider {
        let provider = NSItemProvider(contentsOf: file)!
        provider.suggestedName = file.deletingPathExtension().lastPathComponent
        return provider
    }

    private func waitUntilFinished(_ model: ShareModel) async throws {
        for _ in 0..<200 where model.state == .copying { try await Task.sleep(for: .milliseconds(25)) }
    }

    func testExtensionCopiesPhotosAndCountsWhatItCouldNotAdd() async throws {
        let source = try makeFolder(), inbox = try makeFolder()
        let providers = [
            provider(for: try makeFile("IMG_1.jpg", in: source, bytes: "photo one")),
            provider(for: try makeFile("clip.mov", in: source, bytes: "movie")),
            NSItemProvider(object: "just text" as NSString),   // neither a photo nor a video
        ]
        let model = ShareModel(inboxRoot: { inbox })
        model.start(providers)
        try await waitUntilFinished(model)
        XCTAssertEqual(model.state, .done(saved: 2, total: 3))

        let share = try XCTUnwrap(SharedInbox.takeNewest(at: inbox))
        // The delivered temporary file is named .jpeg, so the extension changes. The iPhone extension does the same.
        XCTAssertEqual(share.items.map(\.originalName), ["IMG_1.jpeg", "clip.mov"], "kept the shared order and the names")
        XCTAssertEqual(try String(contentsOf: share.items[0].url, encoding: .utf8), "photo one")
    }

    /// Cancel during the last copy. The copy cannot stop part way, but the share must not be finished
    /// (flow review 6.15, 4 Nov 2026). Before, the folder became a complete share and opened on the next launch.
    func testCancelDuringTheLastCopyLeavesNoShare() async throws {
        let source = try makeFolder(), inbox = try makeFolder()
        let file = try makeFile("slow.jpg", in: source, bytes: "slow")
        let slow = NSItemProvider()
        slow.registerFileRepresentation(for: .jpeg, visibility: .all) { completion in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { completion(file, false, nil) }
            return nil
        }
        let model = ShareModel(inboxRoot: { inbox })
        model.start([slow])
        try await Task.sleep(for: .milliseconds(100))
        model.cancel()
        try await Task.sleep(for: .milliseconds(1000))   // the copy ends after 0.5 s
        XCTAssertNil(SharedInbox.takeNewest(at: inbox), "a cancelled share must not wait in the inbox")
        XCTAssertNotEqual(model.state, .done(saved: 1, total: 1))
    }

    func testExtensionLeavesNothingBehindWhenEveryItemFails() async throws {
        let inbox = try makeFolder()
        let model = ShareModel(inboxRoot: { inbox })
        model.start([NSItemProvider(object: "text" as NSString)])
        try await waitUntilFinished(model)
        XCTAssertEqual(model.state, .failed)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: inbox.path), [], "a failed share leaves no folder")
    }

    func testAppAddsTheShareToTheQueueAndEmptiesTheInbox() async throws {
        let source = try makeFolder(), inbox = try makeFolder()
        let extensionSide = ShareModel(inboxRoot: { inbox })
        extensionSide.start([provider(for: try makeFile("A.jpg", in: source, bytes: "a")),
                             provider(for: try makeFile("B.mov", in: source, bytes: "b"))])
        try await waitUntilFinished(extensionSide)

        let model = MacModel()
        Self.alive.append(model)   // freeing a model runs MetricSubscriber.deinit, which crashes in MetricKit; the app never frees it
        await model.importShared(takeShared: { await FileImport.takeShared(inbox: inbox) })

        XCTAssertEqual(model.engine.items.map(\.originalName), ["A.jpeg", "B.mov"])
        XCTAssertEqual(model.engine.items.map(\.kind), [.photo, .video])
        XCTAssertEqual(model.selection, model.engine.items.first?.id, "the first shared item is selected")
        XCTAssertEqual(model.notice, "Added 2 from the share menu.")
        for item in model.engine.items {
            XCTAssertEqual(item.url.deletingLastPathComponent(), TemporaryFiles.directory, "moved out of the inbox")
            XCTAssertTrue(FileManager.default.fileExists(atPath: item.url.path))
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: inbox.path), [], "the inbox is empty")

        // A second call finds nothing and changes nothing.
        await model.importShared(takeShared: { await FileImport.takeShared(inbox: inbox) })
        XCTAssertEqual(model.engine.items.count, 2)

        // Removing a shared item deletes its temporary copy.
        let first = try XCTUnwrap(model.engine.items.first)
        model.remove(first.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.url.path))
        model.remove(try XCTUnwrap(model.engine.items.first).id)
    }

    /// A share that waited for a batch is added when the run ends. Its line goes below the Done line, so the
    /// run's result stays visible (flow review 6.8, 4 Nov 2026).
    func testShareAfterABatchKeepsTheDoneLine() async throws {
        let source = try makeFolder(), inbox = try makeFolder()
        let extensionSide = ShareModel(inboxRoot: { inbox })
        extensionSide.start([provider(for: try makeFile("C.jpg", in: source, bytes: "c"))])
        try await waitUntilFinished(extensionSide)
        let model = MacModel()
        Self.alive.append(model)
        model.notice = "Done: 1 saved."
        await model.importShared(appendNotice: true, takeShared: { await FileImport.takeShared(inbox: inbox) })
        XCTAssertEqual(model.notice, "Done: 1 saved.\nAdded 1 from the share menu.")
        for item in model.engine.items { model.remove(item.id) }
    }

    func testRemovingAFileYouAddedNeverDeletesTheFile() async throws {
        let folder = try makeFolder()
        let file = try makeFile("mine.jpg", in: folder, bytes: "mine")
        let model = MacModel()
        Self.alive.append(model)
        await model.add([file])
        let id = try XCTUnwrap(model.engine.items.first { $0.url.lastPathComponent == "mine.jpg" }?.id)
        model.remove(id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "only the temporary copies of shared files are deleted")
    }
}
