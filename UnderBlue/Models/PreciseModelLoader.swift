import Foundation
import Network
import Observation

/// Gets the precise-mask model (SubjectMask.precise) onto the device for the Labs picker, on iOS 27 and macOS 27.
///
/// It starts when Labs is turned on, and at launch when Labs is already on. Until the model is ready, previews
/// and exports get the base correction with no subject lift, and the picker waits.
///
/// Each start first tries the model already on the device (SubjectMask.preciseModelUsable): one small
/// segmentation, with no download call and no network. Only when that fails does it download. On the iPhone in
/// airplane mode the download call neither finished nor failed, even with the model on disk, and the picker
/// waited for ever (24 Oct 2026). So a download with no progress for `stallLimit` ends, too.
/// The asset status cannot help: it reads "not ready" in every new process. The first real download took
/// 3.9 s on the Mac (subject-lift session).
///
/// Offline (Jake, 24 Oct 2026): when the download fails with no network, the loader waits for one, says so,
/// and downloads by itself once a network comes back. The subject features stay off until then; the base
/// correction always works. A failure with a network present is a plain failure with Try again.
@MainActor @Observable
final class PreciseModelLoader {
    enum State: Equatable { case idle, downloading(Double), ready, failed, waitingForNetwork }

    static let shared = PreciseModelLoader()
    private(set) var state = State.idle
    var isReady: Bool { state == .ready }
    @ObservationIgnored private var monitor: NWPathMonitor?
    @ObservationIgnored private var online = true
    /// Counts runs, so the result of an abandoned download is ignored.
    @ObservationIgnored private var runID = 0
    /// How the current run's download call ended, once it ends. Nil while it runs.
    @ObservationIgnored private var downloadSucceeded: Bool?
    /// A download whose progress does not move for this long has stalled.
    static let stallLimit: Duration = .seconds(30)

    /// Starts once, and again after a failure. Does nothing below 27.
    func start() {
        guard #available(iOS 27, macOS 27, *) else { return }
        switch state {
        case .ready, .downloading: return
        case .idle, .failed, .waitingForNetwork: break
        }
        watchNetwork()
        state = .downloading(0)
        Task { await run() }
    }

    /// Watches the network once started. When it comes back, a waiting or failed download runs again.
    private func watchNetwork() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in self?.networkChanged(satisfied) }
        }
        monitor.start(queue: DispatchQueue(label: "com.underblue.precise-model.network"))
        self.monitor = monitor
    }

    private func networkChanged(_ satisfied: Bool) {
        online = satisfied
        // The first path update can come after a quick offline failure. That failure was the network.
        guard satisfied else { if state == .failed { state = .waitingForNetwork }; return }
        if state == .waitingForNetwork || state == .failed { start() } else { recheck() }
    }

    /// Tries the model on the device again, whatever the state. A download that started offline can stay
    /// pending after the network returns (iPhone, 24 Oct 2026); a usable model ends that wait and drops it.
    /// The picker calls this too, before it says it is waiting.
    func recheck() {
        guard #available(iOS 27, macOS 27, *), state != .ready else { return }
        Task {
            guard await SubjectMask.preciseModelUsable(), state != .ready else { return }
            runID += 1
            state = .ready
        }
    }

    @available(iOS 27, macOS 27, *)
    private func run() async {
        runID += 1
        let id = runID
        downloadSucceeded = nil
        // The model already on the device needs no network.
        if await SubjectMask.preciseModelUsable() { finish(id, .ready); return }
        let manager = ProgressManager(totalCount: 1)
        let download = Task { try await SubjectMask.downloadPreciseModel(progress: manager.subprogress(assigningCount: 1)) }
        Task { [weak self] in
            let ok = (try? await download.value) != nil
            await MainActor.run { if self?.runID == id { self?.downloadSucceeded = ok } }
        }
        // Watch the progress. The download call does not always return, so the watch decides when to stop.
        let clock = ContinuousClock()
        var last = -1.0, moved = clock.now
        while downloadSucceeded == nil {
            let fraction = manager.fractionCompleted
            if fraction != last { last = fraction; moved = clock.now; report(fraction) }
            if clock.now - moved > Self.stallLimit { download.cancel(); break }
            try? await Task.sleep(for: .milliseconds(200))
        }
        if downloadSucceeded == true { finish(id, .ready); return }
        // A model that arrived anyway, for example right before the stall, still counts.
        if await SubjectMask.preciseModelUsable() { finish(id, .ready); return }
        finish(id, online ? .failed : .waitingForNetwork)
    }

    private func finish(_ id: Int, _ result: State) {
        guard id == runID else { return }
        state = result
    }

    private func report(_ fraction: Double) {
        guard case .downloading = state, fraction.isFinite else { return }
        state = .downloading(min(1, max(0, fraction)))
    }
}
