import XCTest
@testable import UnderBlue

@MainActor
final class TrialTests: XCTestCase {
    final class MemoryPersistence: TrialPersistence {
        var value = TrialState()
        var fail = false
        func read() throws -> TrialState { if fail { throw UnderBlueError.trialUnavailable }; return value }
        func write(_ state: TrialState) throws { if fail { throw UnderBlueError.trialUnavailable }; value = state }
    }
    final class Clock { var now = Date(timeIntervalSince1970: 1_800_000_000) }
    private let hour: TimeInterval = 60 * 60

    private func export(_ trial: TrialStore, _ kind: ImportedMedia.Kind) throws {
        try trial.reserve(kind); try trial.commit(kind)
    }

    func testThreeWelcomePhotosThenOneEvery24Hours() throws {
        let persistence = MemoryPersistence(), clock = Clock()
        let trial = TrialStore(persistence: persistence) { clock.now }
        XCTAssertEqual(trial.welcomePhotosLeft, 3)
        for _ in 0..<3 { try export(trial, .photo) }
        // The welcome photos start the wait too: the first day gives 3, not 4.
        XCTAssertFalse(trial.canExport(.photo))
        XCTAssertThrowsError(try trial.reserve(.photo))
        clock.now += 23 * hour
        XCTAssertFalse(trial.canExport(.photo))
        XCTAssertNotNil(trial.waitReason(.photo))
        clock.now += hour
        XCTAssertTrue(trial.canExport(.photo))
        XCTAssertNil(trial.waitReason(.photo))
        try export(trial, .photo)
        XCTAssertFalse(trial.canExport(.photo))
        // The state survives a relaunch.
        let restored = TrialStore(persistence: persistence) { clock.now }
        XCTAssertFalse(restored.canExport(.photo))
        XCTAssertEqual(restored.welcomePhotosLeft, 0)
    }
    func testWelcomePhotosDoNotWait() throws {
        let clock = Clock()
        let trial = TrialStore(persistence: MemoryPersistence()) { clock.now }
        try export(trial, .photo)
        clock.now += 60
        XCTAssertTrue(trial.canExport(.photo))
        XCTAssertEqual(trial.welcomePhotosLeft, 2)
    }
    func testOneTenSecondVideoEvery24HoursIndependentOfPhotos() throws {
        let clock = Clock()
        let trial = TrialStore(persistence: MemoryPersistence()) { clock.now }
        XCTAssertEqual(TrialStore.videoSeconds, 10)
        try export(trial, .video)
        XCTAssertFalse(trial.canExport(.video))
        XCTAssertTrue(trial.canExport(.photo))
        clock.now += 24 * hour
        XCTAssertTrue(trial.canExport(.video))
    }
    func testClockSetBackGivesNothing() throws {
        let clock = Clock()
        let trial = TrialStore(persistence: MemoryPersistence()) { clock.now }
        try export(trial, .video)
        clock.now -= 48 * hour
        XCTAssertFalse(trial.canExport(.video))
    }
    func testClockSetForwardOnlyBorrowsTheNextDay() throws {
        let clock = Clock()
        let real = clock.now
        let trial = TrialStore(persistence: MemoryPersistence()) { clock.now }
        try export(trial, .video)
        clock.now = real + 30 * hour
        try export(trial, .video)
        // Back on the real time: the next video waits until 30 + 24 hours after the first.
        clock.now = real + 25 * hour
        XCTAssertFalse(trial.canExport(.video))
        clock.now = real + 54 * hour
        XCTAssertTrue(trial.canExport(.video))
    }
    /// A first install takes its 3 welcome photos in one run; after that one photo a day (Jake, 4 Nov 2026).
    func testOneRunTakesTheWelcomePhotosThenOne() throws {
        let persistence = MemoryPersistence(), clock = Clock()
        let trial = TrialStore(persistence: persistence, now: { clock.now })
        XCTAssertEqual(trial.allowance(.photo), 3); XCTAssertEqual(trial.allowance(.video), 1)
        XCTAssertThrowsError(try trial.reserve([.photo: 4]))
        try trial.reserve([.photo: 3, .video: 1])
        XCTAssertEqual(persistence.value.pending, "photo:3,video:1")
        XCTAssertEqual(trial.allowance(.photo), 0, "a reservation blocks another run")
        // One photo failed: only the 2 saved ones are used, and the video.
        XCTAssertThrowsError(try trial.commit([.photo: 4]), "more than reserved")
        try trial.commit([.photo: 2, .video: 1])
        XCTAssertEqual(trial.welcomePhotosLeft, 1)
        XCTAssertNil(persistence.value.pending)
        XCTAssertEqual(trial.allowance(.photo), 1); XCTAssertEqual(trial.allowance(.video), 0)
        try trial.reserve([.photo: 1]); try trial.commit([.photo: 1])
        XCTAssertEqual(trial.allowance(.photo), 0, "the welcome photos are used and the wait started")
        clock.now += 24 * hour
        XCTAssertEqual(trial.allowance(.photo), 1); XCTAssertEqual(trial.allowance(.video), 1)
    }
    /// The 1.1.10 pending value is one kind name. It still reads as one export.
    func testOldPendingValueReadsAsOne() {
        XCTAssertEqual(TrialPolicy.pendingCounts("photo"), [.photo: 1])
        XCTAssertEqual(TrialPolicy.pendingCounts("video"), [.video: 1])
        XCTAssertEqual(TrialPolicy.pendingCounts("photo:3,video:1"), [.photo: 3, .video: 1])
        XCTAssertEqual(TrialPolicy.pendingCounts(nil), [:])
    }
    func testRollbackRefundsAndPendingBlocks() throws {
        let trial = TrialStore(persistence: MemoryPersistence())
        try trial.reserve(.photo)
        XCTAssertFalse(trial.canExport(.photo))
        try trial.rollback()
        XCTAssertTrue(trial.canExport(.photo))
        XCTAssertEqual(trial.welcomePhotosLeft, 3)
    }
    func testInterruptedExportRefundsOnNextLaunch() throws {
        let persistence = MemoryPersistence()
        let trial = TrialStore(persistence: persistence)
        try trial.reserve(.video)
        XCTAssertTrue(TrialStore(persistence: persistence).canExport(.video))
    }
    func testPersistenceFailureDoesNotGrantExports() throws {
        let persistence = MemoryPersistence(); persistence.fail = true
        let trial = TrialStore(persistence: persistence)
        XCTAssertFalse(trial.canExport(.photo))
        XCTAssertThrowsError(try trial.reserve(.photo))
    }
    /// The 1.1.9 Keychain value: one free photo and one free video in total, as two flags.
    func testOldTrialMigrates() throws {
        let decoder = JSONDecoder()
        let used = try decoder.decode(TrialState.self, from: Data(#"{"photoUsed":true,"videoUsed":true}"#.utf8))
        XCTAssertEqual(used, TrialState(welcomePhotosUsed: 1))
        XCTAssertEqual(TrialPolicy.welcomePhotosLeft(used), 2)
        XCTAssertNil(TrialPolicy.nextFree(.video, state: used, now: Date()))
        let unused = try decoder.decode(TrialState.self, from: Data(#"{"photoUsed":false,"videoUsed":false,"pending":"photo"}"#.utf8))
        XCTAssertEqual(unused, TrialState(pending: "photo"))
    }
    func testRealKeychainRoundTrip() throws {
        let persistence = KeychainTrialPersistence(service: "com.underblue.test.\(UUID().uuidString)")
        var state = try persistence.read()
        XCTAssertEqual(state.welcomePhotosUsed, 0)
        state.welcomePhotosUsed = 1
        state.lastPhoto = Date(timeIntervalSince1970: 1_800_000_000)
        try persistence.write(state)
        XCTAssertEqual(try persistence.read(), state)
    }
}
