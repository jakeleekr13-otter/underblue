import XCTest
import Synchronization
@testable import UnderBlue

/// A memory reading the test controls.
private final class FakeProbe: MemoryProbe, @unchecked Sendable {
    let physicalBytes: UInt64
    private let available: Mutex<UInt64>
    init(physicalGB: UInt64, availableGB: Double) {
        physicalBytes = physicalGB << 30
        available = Mutex(UInt64(availableGB * 1_073_741_824))
    }
    func availableBytes() -> UInt64 { available.withLock { $0 } }
    func set(availableGB: Double) { available.withLock { $0 = UInt64(availableGB * 1_073_741_824) } }
}

private let gb: UInt64 = 1 << 30

final class MemoryGovernorTests: XCTestCase {
    /// No settle time and a short poll, so tests do not wait.
    private func fast() -> MemoryGovernor.Config {
        var config = MemoryGovernor.Config()
        config.settle = .zero
        config.poll = .milliseconds(5)
        return config
    }

    /// True when `work` has not finished after `milliseconds`. Cancels it afterwards.
    private func staysBlocked(_ work: Task<MemoryGovernor.Reservation, Error>, for milliseconds: Int = 120) async -> Bool {
        let finished = Mutex(false)
        let watcher = Task { _ = try? await work.value; finished.withLock { $0 = true } }
        try? await Task.sleep(for: .milliseconds(milliseconds))
        let blocked = !finished.withLock { $0 }
        if blocked { work.cancel() }
        _ = await watcher.value
        return blocked
    }

    func testFirstExportAlwaysStartsEvenWhenItIsHugeAndMemoryIsLow() async throws {
        let governor = MemoryGovernor(probe: FakeProbe(physicalGB: 8, availableGB: 0.1), config: fast())
        let reservation = try await governor.acquire(cost: 6 * gb)
        let running = await governor.running
        XCTAssertEqual(running, 1)
        await governor.release(reservation)
    }

    func testSecondExportWaitsForAvailableMemoryThenStarts() async throws {
        let probe = FakeProbe(physicalGB: 32, availableGB: 2)
        let governor = MemoryGovernor(probe: probe, config: fast())
        let first = try await governor.acquire(cost: 2 * gb)
        // Needs 2 GB + the 1 GB reserve; only 2 GB are available.
        let second = Task { try await governor.acquire(cost: 2 * gb) }
        let blocked = await staysBlocked(second)
        XCTAssertTrue(blocked, "must wait while available memory is short")
        probe.set(availableGB: 3.5)
        let third = try await governor.acquire(cost: 2 * gb)
        let running = await governor.running
        XCTAssertEqual(running, 2)
        await governor.release(first); await governor.release(third)
    }

    func testSecondExportWaitsWhenTheBudgetIsFullThenStartsAfterARelease() async throws {
        // 8 GB Mac: budget 0.7 x 8 = 5.6 GB. Plenty is available, so only the budget decides.
        let governor = MemoryGovernor(probe: FakeProbe(physicalGB: 8, availableGB: 7), config: fast())
        let first = try await governor.acquire(cost: 3 * gb)
        let second = Task { try await governor.acquire(cost: 3 * gb) }
        let blocked = await staysBlocked(second)
        XCTAssertTrue(blocked, "3 GB + 3 GB is over the 5.6 GB budget")
        await governor.release(first)
        let again = try await governor.acquire(cost: 3 * gb)
        await governor.release(again)
    }

    func testMemoryPressureStopsNewStartsUntilItClears() async throws {
        let governor = MemoryGovernor(probe: FakeProbe(physicalGB: 32, availableGB: 20), config: fast())
        let first = try await governor.acquire(cost: gb)
        await governor.setPressure(.warning)
        let blocked = await staysBlocked(Task { try await governor.acquire(cost: gb) })
        XCTAssertTrue(blocked, "warning blocks a second export")
        await governor.setPressure(.normal)
        let second = try await governor.acquire(cost: gb)
        await governor.release(first); await governor.release(second)
        // With nothing running, pressure does not block: the batch must still make progress.
        await governor.setPressure(.critical)
        let alone = try await governor.acquire(cost: gb)
        await governor.release(alone)
    }

    func testStartsAreSpacedBySettleTime() async throws {
        var config = fast()
        config.settle = .milliseconds(300)
        let governor = MemoryGovernor(probe: FakeProbe(physicalGB: 64, availableGB: 50), config: config)
        let first = try await governor.acquire(cost: gb)
        let clock = ContinuousClock()
        let started = clock.now
        let second = try await governor.acquire(cost: gb)
        let waited = clock.now - started
        XCTAssertGreaterThanOrEqual(waited, .milliseconds(250), "second start waits for the settle time")
        await governor.release(first); await governor.release(second)
    }

    func testCancelledWaiterThrowsAndLeavesNothingReserved() async throws {
        let governor = MemoryGovernor(probe: FakeProbe(physicalGB: 8, availableGB: 0.5), config: fast())
        let first = try await governor.acquire(cost: gb)
        let waiter = Task { try await governor.acquire(cost: gb) }
        try await Task.sleep(for: .milliseconds(50))
        waiter.cancel()
        do { _ = try await waiter.value; XCTFail("a cancelled wait must throw") } catch is CancellationError {}
        let running = await governor.running, waiting = await governor.waiting
        XCTAssertEqual(running, 1)
        XCTAssertEqual(waiting, 0)
        await governor.release(first)
    }

    func testCostFollowsMeasuredPointsAndStopsAtTheCap() {
        let governor = MemoryGovernor(probe: FakeProbe(physicalGB: 16, availableGB: 8), config: fast())
        func gigabytes(_ mp: Double) -> Double { Double(governor.cost(megapixels: mp)) / Double(gb) }
        // Measured on a 16 GB Mac: 2.1 MP took 0.74-0.88 GB, 8 MP took 3.1-3.5 GB, 50 MP took 5.2-5.4 GB.
        XCTAssertEqual(gigabytes(2.1), 0.88, accuracy: 0.1)
        XCTAssertEqual(gigabytes(8.0), 3.36, accuracy: 0.3)
        XCTAssertEqual(gigabytes(49.9), 5.44, accuracy: 0.1, "capped at 34% of 16 GB")
        XCTAssertEqual(gigabytes(0), 64.0 / 1024, accuracy: 0.001, "never below the minimum")
        XCTAssertEqual(gigabytes(.nan), 5.44, accuracy: 0.1, "an unknown size counts as the cap")
    }

    /// The engine must not run more exports at once than the governor allows.
    @MainActor
    func testEngineRunsOneExportAtATimeWhenMemoryIsTight() async throws {
        let probe = FakeProbe(physicalGB: 8, availableGB: 0.5)
        let governor = MemoryGovernor(probe: probe, config: fast())
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("GovernorEngine-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: output) }
        let diagnostics = DiagnosticRecorder(directory: FileManager.default.temporaryDirectory.appendingPathComponent("GovernorDiag-\(UUID().uuidString)"))
        let engine = BatchEngine(limits: .init(analysis: 1, videoExport: 1, photoExport: 4, inFlight: 6),
                                 sink: DirectorySink(directory: output), diagnostics: diagnostics, memory: governor)
        var media: [ImportedMedia] = []
        for index in 0..<4 {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("GovernorSrc-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("p\(index).heic")
            let image = CIImage(color: CIColor(red: 0.1, green: 0.5, blue: 0.7)).cropped(to: CGRect(x: 0, y: 0, width: 600, height: 400))
            try FilterEngine().context.writeHEIFRepresentation(of: image, to: url, format: .RGBA8, colorSpace: FilterEngine.photoSpace)
            media.append(ImportedMedia(url: url, kind: .photo, originalName: "p\(index).heic"))
        }
        defer { media.forEach { try? FileManager.default.removeItem(at: $0.url.deletingLastPathComponent()) } }
        engine.add(media)
        engine.start(settings: FilterSettings())
        await engine.waitUntilFinished()
        XCTAssertEqual(engine.items.map(\.state), Array(repeating: .done, count: 4), engine.items.compactMap(\.error).joined(separator: "; "))
        // Available memory (0.5 GB) is below the 1 GB reserve alone, so a second export never starts while one runs.
        let most = await governor.maxConcurrent
        XCTAssertEqual(most, 1)
    }
}
