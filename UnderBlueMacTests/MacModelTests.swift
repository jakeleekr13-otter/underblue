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
