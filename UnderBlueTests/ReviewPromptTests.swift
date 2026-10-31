import XCTest
@testable import UnderBlue

final class ReviewPromptTests: XCTestCase {
    private func emptyDefaults() throws -> UserDefaults {
        let name = "ReviewPromptTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return defaults
    }

    func testAsksOnlyOnlineFromTheTenthSaveOncePerVersion() throws {
        let defaults = try emptyDefaults()
        let prompt = ReviewPrompt(defaults: defaults, version: "1.2")
        prompt.recordSaves(9)
        XCTAssertFalse(prompt.shouldAsk(online: true))
        prompt.recordSaves(1)
        XCTAssertFalse(prompt.shouldAsk(online: false))
        XCTAssertTrue(prompt.shouldAsk(online: true))
        prompt.markAsked()
        XCTAssertFalse(prompt.shouldAsk(online: true))
        XCTAssertTrue(ReviewPrompt(defaults: defaults, version: "1.3").shouldAsk(online: true))
    }

    func testABatchCountsEverySavedPhoto() throws {
        let prompt = ReviewPrompt(defaults: try emptyDefaults(), version: "1.2")
        prompt.recordSaves(0)
        XCTAssertEqual(prompt.saves, 0)
        prompt.recordSaves(12)
        XCTAssertEqual(prompt.saves, 12)
        XCTAssertTrue(prompt.shouldAsk(online: true))
    }
}
