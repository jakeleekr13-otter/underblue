import Foundation
import ImageIO

/// Runs many photos and videos through analyse → export → deliver.
///
/// Each stage has its own job limit, so the CPU analyses the next video while the GPU exports the current
/// one. Results are delivered one by one, in queue order, even when a later item finishes first.
/// A cancelled run keeps what is done. `start()` again resumes the rest.
///
/// The engine does not check Pro access and does not ask for permissions. The screen that owns it does.
@MainActor @Observable
final class BatchEngine {
    enum State: Equatable, Sendable { case queued, analyzing, waiting, waitingForMemory, exporting, delivering, done, failed, cancelled }

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
    /// Change these only while no run is active. A run reads them once, when it starts.
    var limits: Limits
    /// Keep HDR in photos and videos when the source and the Mac allow it. Off exports SDR.
    var preferHDR = true
    /// Where results go. Set it before `start()`. A run keeps the sink it started with.
    var sink: BatchSink
    private let diagnostics: DiagnosticRecorder
    private let memory: MemoryGovernor
    private var runTask: Task<Void, Never>?
    private var itemTasks: [Task<Void, Never>] = []

    init(limits: Limits = Limits(), sink: BatchSink, diagnostics: DiagnosticRecorder, memory: MemoryGovernor = MemoryGovernor()) {
        self.limits = limits
        self.memory = memory
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
    /// `trial` applies the free-trial limits to every item: photos export as SDR, videos as 1080p SDR for the first seconds only.
    func start(settings: FilterSettings, photoFormat: ExportOptions.PhotoFormat = .jpeg, trial: Bool = false) {
        guard !running else { return }
        let ids = items.filter { $0.state == .queued || $0.state == .cancelled }.map(\.id)
        guard !ids.isEmpty else { return }
        for id in ids { update(id) { $0.state = .queued; $0.progress = 0; $0.error = nil } }
        running = true
        runTask = Task {
            await run(ids, settings: settings, photoFormat: photoFormat, trial: trial)
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
        let trial: Bool
        let preferHDR: Bool
        let memory: MemoryGovernor
        let sink: BatchSink
    }

    private func run(_ ids: [Item.ID], settings: FilterSettings, photoFormat: ExportOptions.PhotoFormat, trial: Bool) async {
        let workers = Workers(
            analysis: StageGate(limit: limits.analysis), video: StageGate(limit: limits.videoExport),
            photo: StageGate(limit: limits.photoExport), window: StageGate(limit: limits.inFlight),
            // One worker per export slot. A worker keeps the depth result of its photos until that photo is exported.
            processors: (0..<max(1, limits.photoExport)).map { _ in PhotoProcessor(diagnostics: diagnostics) },
            analyzer: VideoRestorationAnalyzer(diagnostics: diagnostics),
            exporters: (0..<max(1, limits.videoExport)).map { _ in VideoExporter(diagnostics: diagnostics) },
            base: settings, format: photoFormat, trial: trial, preferHDR: preferHDR, memory: memory, sink: sink)
        await memory.startObservingPressure()
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
        await memory.stopObservingPressure()
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
            let saved = try await workers.sink.deliver(produced, fileName: name, kind: item.kind)
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
        let chosen = settings, format = workers.format, url = item.url, id = item.id
        let cost = workers.memory.cost(megapixels: Self.megapixels(ofPhoto: url))
        do {
            let output = try await workers.photo.run { slot in
                await self.update(id) { $0.state = .waitingForMemory }
                let reservation = try await workers.memory.acquire(cost: cost)
                do {
                    await self.update(id) { $0.state = .exporting }
                    try StorageCheck.require(bytes: 100_000_000)
                    // Batch has no SDR/HDR choice: HDR photos stay HDR, SDR photos stay SDR.
                    let file = try await workers.processors[slot].export(url, settings: chosen, keepHDR: !workers.trial && workers.preferHDR, format: format)
                    await workers.memory.release(reservation)
                    return file
                } catch { await workers.memory.release(reservation); throw error }
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
            if workers.trial {
                options.resolution = .hd; options.range = .sdr; options.durationLimit = TrialStore.videoSeconds
            } else {
                options.resolution = .source
                let hdr = workers.preferHDR ? await ExportCapability.evaluate(url: url, metadata: metadata).hdrAvailable : false
                options.range = hdr ? .hdr : .sdr
            }
        } catch { await workers.analysis.release(analysisSlot); throw error }
        await workers.analysis.release(analysisSlot)
        update(item.id) { $0.state = .waiting }
        let chosen = settings, chosenOptions = options, found = analysis, id = item.id, url = item.url
        let size = metadata.displaySize
        let cost = workers.memory.cost(megapixels: Double(size.width * size.height) / 1_000_000)
        let result = try await workers.video.run { slot in
            await self.update(id) { $0.state = .waitingForMemory }
            let reservation = try await workers.memory.acquire(cost: cost)
            do {
                await self.update(id) { $0.state = .exporting }
                let done = try await workers.exporters[slot].export(url: url, metadata: metadata, settings: chosen, options: chosenOptions,
                                                                     restorationAnalysis: found) { value in
                    await self.update(id) { $0.progress = value }
                }
                await workers.memory.release(reservation)
                return done
            } catch { await workers.memory.release(reservation); throw error }
        }
        return (result.url, settings)
    }

    /// The pixel count of a photo in megapixels, read from the file header. A file that cannot be read counts as 12 MP.
    nonisolated static func megapixels(ofPhoto url: URL) -> Double {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double, let height = properties[kCGImagePropertyPixelHeight] as? Double,
              width > 0, height > 0 else { return 12 }
        return width * height / 1_000_000
    }

    private func update(_ id: Item.ID, _ change: (inout Item) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }
}
