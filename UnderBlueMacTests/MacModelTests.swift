import XCTest
@testable import UnderBlue

@MainActor
final class MacModelTests: XCTestCase {
    private static var alive: [MacModel] = []

    /// An item that an earlier run saved must not count for this run. Before 4 Nov 2026 a free run that saved
    /// nothing still used the trial when the queue held an older finished item (flow review 6.2).
    func testRunResultCountsOnlyThisRun() {
        let url = URL(fileURLWithPath: "/tmp/none.heic")
        let earlier = BatchEngine.Item(url: url, kind: .photo, state: .done)
        let failed = BatchEngine.Item(url: url, kind: .photo, state: .failed)
        let saved = BatchEngine.Item(url: url, kind: .photo, state: .done)
        let nothing = MacModel.runResult([earlier, failed], runIDs: [failed.id])
        XCTAssertEqual(nothing.done, 0); XCTAssertEqual(nothing.failed, 1)
        let one = MacModel.runResult([earlier, saved], runIDs: [saved.id])
        XCTAssertEqual(one.done, 1); XCTAssertEqual(one.failed, 0)
    }
    /// A free queue takes what one free run may correct; the rest is dropped (Jake, 4 Nov 2026).
    func testFreeQueueKeepsTheAllowanceOfEachKind() {
        func media(_ name: String, _ kind: ImportedMedia.Kind) -> ImportedMedia {
            ImportedMedia(url: URL(fileURLWithPath: "/tmp/\(name)"), kind: kind, originalName: name)
        }
        let files = [media("1.jpg", .photo), media("a.mov", .video), media("2.jpg", .photo), media("3.jpg", .photo),
                     media("4.jpg", .photo), media("b.mov", .video)]
        let first = MacModel.fitTrial(files, photoRoom: 3, videoRoom: 1)
        XCTAssertEqual(first.kept.map(\.originalName), ["1.jpg", "a.mov", "2.jpg", "3.jpg"])
        XCTAssertEqual(first.dropped.map(\.originalName), ["4.jpg", "b.mov"])
        XCTAssertEqual(MacModel.fitTrial(files, photoRoom: 1, videoRoom: 0).kept.map(\.originalName), ["1.jpg"])
    }
    /// Each saved item of the run uses one free export of its kind. Older finished items do not count.
    func testSavedKindsCountOnlyThisRun() {
        let url = URL(fileURLWithPath: "/tmp/none.heic")
        let older = BatchEngine.Item(url: url, kind: .photo, state: .done)
        let photo = BatchEngine.Item(url: url, kind: .photo, state: .done)
        let failed = BatchEngine.Item(url: url, kind: .photo, state: .failed)
        let video = BatchEngine.Item(url: url, kind: .video, state: .done)
        let saved = MacModel.savedKinds([older, photo, failed, video], runIDs: [photo.id, failed.id, video.id])
        XCTAssertEqual(saved, [.photo: 1, .video: 1])
    }
    /// A setting that clamps itself inside didSet once looped forever and crashed the app (20 Oct 2026).
    func testParallelPhotosAcceptsEveryValueAndClampsTheEngineLimit() {
        let key = "mac.parallelPhotos"
        let saved = UserDefaults.standard.object(forKey: key)
        defer { if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }

        let model = MacModel()
        // The model stays alive for the whole test run. Freeing it runs MetricSubscriber.deinit, which crashes in MetricKit;
        // the app never frees it, so the app is not affected.
        Self.alive.append(model)
        for (value, expected) in [(3, 3), (1, 1), (4, 4), (9, 4), (0, 1), (-5, 1)] {
            model.parallelPhotos = value
            XCTAssertEqual(model.engine.limits.photoExport, expected, "parallelPhotos = \(value)")
            XCTAssertEqual(UserDefaults.standard.integer(forKey: key), expected, "saved value for \(value)")
        }
    }
}
