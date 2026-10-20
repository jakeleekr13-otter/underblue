import Dispatch
import Foundation
import Darwin

/// Reads the memory of the Mac. A fake one makes the governor testable.
protocol MemoryProbe: Sendable {
    var physicalBytes: UInt64 { get }
    /// Memory that can be used now without pushing other data out: free plus inactive pages.
    func availableBytes() -> UInt64
}

struct SystemMemoryProbe: MemoryProbe {
    var physicalBytes: UInt64 { ProcessInfo.processInfo.physicalMemory }

    func availableBytes() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return 0 }
        // free_count already includes speculative pages. Purgeable pages sit inside other counts, so they are not added.
        return (UInt64(stats.free_count) + UInt64(stats.inactive_count)) * UInt64(sysconf(_SC_PAGESIZE))
    }
}

/// Decides when the next photo or video export may start, so the batch does not use more memory than the Mac has.
///
/// An export is the big cost. Analysis stays below 0.3 GB for a 50 MP photo, and an export takes up to 5.4 GB
/// (measured 20 Oct 2026, see MemoryProfileTests). So every export asks here first and gives its share back when it ends.
///
/// Rules:
/// - With nothing running, an export always starts. Otherwise one huge file could wait forever.
/// - With others running, it starts only when all of these hold: the shared budget has room, the Mac reports
///   enough available memory, the Mac reports no memory pressure, and the last start is a few seconds old.
///   The last rule gives the running export time to take its memory, so the available figure is true.
actor MemoryGovernor {
    enum Pressure: Int, Sendable { case normal, warning, critical }

    struct Config: Sendable {
        /// Share of the physical memory that all running exports together may reserve.
        var budgetFraction = 0.7
        /// One export never costs more than this share of the physical memory.
        /// 0.34 is what a 16 GB Mac showed (5.4 GB). Other memory sizes are not measured.
        var capFraction = 0.34
        /// Export cost per megapixel, below the cap. Measured on a 16 GB Mac (Mac15,12): 2.1 MP took 0.74 to 0.88 GB,
        /// 8 MP took 3.1 to 3.5 GB, photos and videos alike. Videos were measured on 0.3 to 0.6 s clips only.
        var bytesPerMegapixel = 0.42 * 1_073_741_824
        var minimumCost: UInt64 = 64 * 1_048_576
        /// Available memory that must remain after a new export is counted in.
        var reserveBytes: UInt64 = 1_073_741_824
        /// Time between two starts while another export runs. Memory reached 4.7 GB within 2 s of a start.
        var settle: Duration = .seconds(2)
        var poll: Duration = .milliseconds(250)
    }

    struct Reservation: Sendable, Equatable { fileprivate let id: UInt64 }

    private let probe: MemoryProbe
    let config: Config
    private let physical: UInt64
    private var reservations: [UInt64: UInt64] = [:]
    private var nextID: UInt64 = 0
    private var lastGrant: ContinuousClock.Instant?
    private(set) var pressure = Pressure.normal
    private(set) var waiting = 0
    /// Highest number of exports that ran at the same time. For tests and diagnostics.
    private(set) var maxConcurrent = 0
    private var pressureSource: DispatchSourceMemoryPressure?

    init(probe: MemoryProbe = SystemMemoryProbe(), config: Config = Config()) {
        self.probe = probe
        self.config = config
        physical = probe.physicalBytes
    }

    deinit { pressureSource?.cancel() }

    var reservedBytes: UInt64 { reservations.values.reduce(0, +) }
    var running: Int { reservations.count }
    var budgetBytes: UInt64 { UInt64(Double(physical) * config.budgetFraction) }

    /// The cost of one export of `megapixels`.
    nonisolated func cost(megapixels: Double) -> UInt64 {
        let cap = Double(probe.physicalBytes) * config.capFraction
        let raw = max(Double(config.minimumCost), megapixels.isFinite ? megapixels * config.bytesPerMegapixel : cap)
        return UInt64(min(cap, raw))
    }

    /// Waits until an export of `cost` may start. Throws CancellationError if the task is cancelled while it waits.
    func acquire(cost: UInt64) async throws -> Reservation {
        waiting += 1
        defer { waiting -= 1 }
        while true {
            try Task.checkCancellation()
            if canStart(cost) { return grant(cost) }
            try await Task.sleep(for: config.poll)
        }
    }

    func release(_ reservation: Reservation) {
        reservations[reservation.id] = nil
    }

    private func canStart(_ cost: UInt64) -> Bool {
        if reservations.isEmpty { return true }
        guard pressure == .normal else { return false }
        if let lastGrant, ContinuousClock.now - lastGrant < config.settle { return false }
        guard reservedBytes + cost <= budgetBytes else { return false }
        return probe.availableBytes() >= cost + config.reserveBytes
    }

    private func grant(_ cost: UInt64) -> Reservation {
        nextID += 1
        reservations[nextID] = cost
        lastGrant = .now
        maxConcurrent = max(maxConcurrent, reservations.count)
        return Reservation(id: nextID)
    }

    // MARK: Memory pressure

    func setPressure(_ value: Pressure) { pressure = value }

    /// Follows the system's memory-pressure events. Call once before a run, and `stopObservingPressure()` after it.
    func startObservingPressure() {
        guard pressureSource == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .global(qos: .utility))
        source.setEventHandler { [weak self, weak source] in
            guard let self, let event = source?.data else { return }
            let value: Pressure = event.contains(.critical) ? .critical : event.contains(.warning) ? .warning : .normal
            Task { await self.setPressure(value) }
        }
        source.resume()
        pressureSource = source
    }

    func stopObservingPressure() {
        pressureSource?.cancel()
        pressureSource = nil
        pressure = .normal
    }
}
