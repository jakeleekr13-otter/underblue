import XCTest
@testable import UnderBlue

@MainActor
final class MacModelTests: XCTestCase {
    private static var alive: [MacModel] = []

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
