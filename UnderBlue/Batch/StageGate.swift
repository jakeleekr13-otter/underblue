import Foundation

/// Limits one stage of the batch pipeline to a fixed number of jobs at once.
/// Jobs get a slot in the order they ask. A slot number lets a stage keep one worker per slot.
actor StageGate {
    private var free: [Int]
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Int, Error>)] = []

    init(limit: Int) { free = Array(0..<max(1, limit)) }

    func acquire() async throws -> Int {
        try Task.checkCancellation()
        if !free.isEmpty { return free.removeFirst() }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // The cancel handler may have run before this point, so check again.
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { waiters.append((id, continuation)) }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    func release(_ slot: Int) {
        if waiters.isEmpty { free.append(slot) } else { waiters.removeFirst().continuation.resume(returning: slot) }
    }

    /// Runs `work` in a slot and gives the slot back when it ends, with a result or an error.
    func run<T: Sendable>(_ work: @Sendable (Int) async throws -> T) async throws -> T {
        let slot = try await acquire()
        do {
            let value = try await work(slot)
            release(slot)
            return value
        } catch {
            release(slot)
            throw error
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
