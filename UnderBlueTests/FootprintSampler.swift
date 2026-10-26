import Darwin
import Foundation
import Synchronization

/// The process memory footprint, sampled on its own thread every 2 ms (PhotoCostProbeTests, PressProbeTests).
/// The two values the thread shares with the test are atomics. Raw pointers were a data race: the thread wrote
/// the peak while the test read it, and nothing told the compiler that `running` could change.
final class FootprintSampler: Sendable {
    let start: UInt64
    private let peak: Atomic<UInt64>
    private let running = Atomic<Bool>(true)

    init() {
        start = Self.footprint()
        peak = Atomic(start)
    }

    static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    func begin() {
        Thread { [self] in
            while running.load(ordering: .relaxed) {
                peak.max(Self.footprint(), ordering: .relaxed)
                usleep(2000)
            }
        }.start()
    }

    /// Stops the thread and returns the peak over the start, in MB.
    func end() -> Double {
        running.store(false, ordering: .relaxed)
        usleep(5000)
        return Double(Int64(peak.load(ordering: .relaxed)) - Int64(start)) / 1_048_576
    }
}
