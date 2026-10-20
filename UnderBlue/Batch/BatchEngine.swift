import Foundation

/// Runs many photos and videos through analyse → export → deliver.
///
/// Each stage has its own job limit, so the CPU analyses the next video while the GPU exports the current
/// one. Results are delivered one by one, in queue order, even when a later item finishes first.
/// A cancelled run keeps what is done. `start()` again resumes the rest.
///
/// The engine does not check Pro access and does not ask for permissions. The screen that owns it does.
@MainActor @Observable
final class BatchEngine {
    enum State: Equatable, Sendable { case queued, analyzing, waiting, exporting, delivering, done, failed, cancelled }

    struct Item: Identifiable, Sendable {
        let id = UUID()
        let url: URL
        let kind: ImportedMedia.Kind
        var originalName: String?
        var state = State.queued
        /// 0...1 while exporting a video. A photo has no progress, only a state.
        var progress = 0.0
        /// The name the sink stored the result under.
        var savedName: String?
        var error: String?
    }

    /// Jobs allowed at once in each stage. `inFlight` caps the items that were admitted but are not delivered yet,
    /// so finished files waiting for their turn do not pile up on disk.
    struct Limits: Sendable, Equatable {
        var analysis = 1
        var videoExport = 1
        var photoExport = 1
        var inFlight = 4
    }

    private(set) var items: [Item] = []
    private(set) var running = false
    let limits: Limits
    private let sink: BatchSink
    private let diagnostics: DiagnosticRecorder
    private var runTask: Task<Void, Never>?
    private var itemTasks: [Task<Void, Never>] = []

    init(limits: Limits = Limits(), sink: BatchSink, diagnostics: DiagnosticRecorder) {
        self.limits = limits
        self.sink = sink
        self.diagnostics = diagnostics
    }

    var doneCount: Int { items.filter { $0.state == .done }.count }
    var failedCount: Int { items.filter { $0.state == .failed }.count }
    /// Items a `start()` would run now.
    var pendingCount: Int { items.filter { $0.state == .queued || $0.state == .cancelled }.count }

    func add(_ media: [ImportedMedia]) {
        items += media.map { Item(url: $0.url, kind: $0.kind, originalName: $0.originalName) }
    }

    /// Removes an item that is not running. Returns false while a run is active.
    @discardableResult
    func remove(_ id: Item.ID) -> Bool {
        guard !running else { return false }
        items.removeAll { $0.id == id }
        return true
    }

    func retryFailed() {
        guard !running else { return }
        for index in items.indices where items[index].state == .failed { items[index].state = .queued }
    }

    /// Starts every queued or cancelled item. It does nothing while a run is active.
    func start(settings: FilterSettings, photoFormat: ExportOptions.PhotoFormat = .jpeg) {
        guard !running else { return }
        let ids = items.filter { $0.state == .queued || $0.state == .cancelled }.map(\.id)
        guard !ids.isEmpty else { return }
        for id in ids { update(id) { $0.state = .queued; $0.progress = 0; $0.error = nil } }
        running = true
        runTask = Task {
            await run(ids, settings: settings, photoFormat: photoFormat)
            running = false; runTask = nil; itemTasks = []
        }
    }

    func cancel() {
        runTask?.cancel()
        for task in itemTasks { task.cancel() }
    }

    /// Returns when the current run has ended. For tests and for a window that waits before it quits.
    func waitUntilFinished() async { await runTask?.value }

    // MARK: - Pipeline

    private struct Workers: Sendable {
        let analysis: StageGate, video: StageGate, photo: StageGate, window: StageGate
        let processors: [PhotoProcessor]
        let analyzer: VideoRestorationAnalyzer
        let exporters: [VideoExporter]
        let base: FilterSettings
        let format: ExportOptions.PhotoFormat
    }

    private func run(_ ids: [Item.ID], settings: FilterSettings, photoFormat: ExportOptions.PhotoFormat) async {
        let workers = Workers(
            analysis: StageGate(limit: limits.analysis), video: StageGate(limit: limits.videoExport),
            photo: StageGate(limit: limits.photoExport), window: StageGate(limit: limits.inFlight),
            // One worker per export slot. A worker keeps the depth result of its photos until that photo is exported.
            processors: (0..<max(1, limits.photoExport)).map { _ in PhotoProcessor(diagnostics: diagnostics) },
            analyzer: VideoRestorationAnalyzer(diagnostics: diagnostics),
            exporters: (0..<max(1, limits.videoExport)).map { _ in VideoExporter(diagnostics: diagnostics) },
            base: settings, format: photoFormat)
        var previous: Task<Void, Never>?
        do {
            for id in ids {
                // Admission is in queue order: the window first, then the analysis slot.
                _ = try await workers.window.acquire()
                let slot: Int
                do { slot = try await workers.analysis.acquire() } catch { await workers.window.release(0); throw error }
                let turn = previous
                let task = Task { await process(id, analysisSlot: slot, workers: workers, after: turn) }
                previous = task
                itemTasks.append(task)
            }
        } catch { /* cancelled while waiting for admission */ }
        for task in itemTasks { await task.value }
        // Items that were never admitted because of a cancel go back to a state a new run can pick up.
        for id in ids { update(id) { if $0.state == .queued { $0.state = .cancelled } } }
    }

    private func process(_ id: Item.ID, analysisSlot: Int, workers: Workers, after previous: Task<Void, Never>?) async {
        guard let item = items.first(where: { $0.id == id }) else {
            await workers.analysis.release(analysisSlot); await workers.window.release(0); return
        }
        var output: URL?
        var settings = workers.base
        var operation = Operation.export
        do {
            let produced: URL
            switch item.kind {
            case .photo: (produced, settings) = try await processPhoto(item, analysisSlot: analysisSlot, workers: workers)
            case .video: (produced, settings) = try await processVideo(item, analysisSlot: analysisSlot, workers: workers)
            }
            output = produced
            update(id) { $0.state = .waiting }
            // Delivery waits for every earlier item, so results land in queue order.
            await previous?.value
            try Task.checkCancellation()
            update(id) { $0.state = .delivering }
            operation = .save
            let name = ExportNaming.fileName(source: item.originalName, preset: settings.preset, extension: produced.pathExtension)
            let saved = try await sink.deliver(produced, fileName: name, kind: item.kind)
            update(id) { $0.state = .done; $0.progress = 1; $0.savedName = saved }
        } catch is CancellationError {
            update(id) { $0.state = .cancelled }
        } catch {
            let failure = Failure.classify(error, operation: operation)
            if failure.kind == .cancelled {
                update(id) { $0.state = .cancelled }
            } else {
                update(id) { $0.state = .failed; $0.error = failure.message }
                await diagnostics.record(failure, operation: operation)
            }
        }
        // A file that was not delivered is removed. A delivered file was moved, so there is nothing left to remove.
        TemporaryFiles.remove(output)
        await workers.window.release(0)
    }

    private func processPhoto(_ item: Item, analysisSlot: Int, workers: Workers) async throws -> (URL, FilterSettings) {
        let processor = workers.processors[analysisSlot % workers.processors.count]
        var settings = workers.base
        update(item.id) { $0.state = .analyzing }
        do { settings.analysis = try await processor.analyze(item.url) }
        catch { await workers.analysis.release(analysisSlot); await processor.forget(item.url); throw error }
        await workers.analysis.release(analysisSlot)
        update(item.id) { $0.state = .waiting }
        let chosen = settings, format = workers.format, url = item.url
        do {
            let output = try await workers.photo.run { slot in
                await self.update(item.id) { $0.state = .exporting }
                try StorageCheck.require(bytes: 100_000_000)
                // Batch has no SDR/HDR choice: HDR photos stay HDR, SDR photos stay SDR.
                return try await workers.processors[slot].export(url, settings: chosen, keepHDR: true, format: format)
            }
            await processor.forget(url)
            return (output, settings)
        } catch { await processor.forget(url); throw error }
    }

    private func processVideo(_ item: Item, analysisSlot: Int, workers: Workers) async throws -> (URL, FilterSettings) {
        var settings = workers.base
        let metadata: VideoMetadata
        var analysis: VideoRestorationAnalysis?
        var options = ExportOptions()
        update(item.id) { $0.state = .analyzing }
        do {
            let url = item.url
            metadata = try await SafeReadRetry().run(operation: .inspection) { try await MediaInspector().inspect(url) }
            do {
                analysis = try await workers.analyzer.analyze(url: url, metadata: metadata)
            } catch is CancellationError { throw CancellationError() } catch {
                // Like the editor: without a scene analysis the video still follows the look, so it is not a failure.
                await diagnostics.record(Failure.restorationFallback(.videoSceneAnalysis), operation: .videoRestoration)
            }
            settings.analysis = analysis?.legacyAnalysis ?? .neutral
            options.resolution = .source
            options.range = await ExportCapability.evaluate(url: url, metadata: metadata).hdrAvailable ? .hdr : .sdr
        } catch { await workers.analysis.release(analysisSlot); throw error }
        await workers.analysis.release(analysisSlot)
        update(item.id) { $0.state = .waiting }
        let chosen = settings, chosenOptions = options, found = analysis, id = item.id, url = item.url
        let result = try await workers.video.run { slot in
            await self.update(id) { $0.state = .exporting }
            return try await workers.exporters[slot].export(url: url, metadata: metadata, settings: chosen, options: chosenOptions,
                                                             restorationAnalysis: found) { value in
                await self.update(id) { $0.progress = value }
            }
        }
        return (result.url, settings)
    }

    private func update(_ id: Item.ID, _ change: (inout Item) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }
}
