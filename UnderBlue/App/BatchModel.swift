import SwiftUI

/// Pro-only batch correction. Every photo gets its own water analysis. One shared look
/// (preset + intensity) applies to all, and a photo may override it. Custom uses the one saved
/// set of CustomAdjustments for every photo.
@MainActor @Observable
final class BatchModel: Identifiable {
    nonisolated static let maxPhotos = 10
    nonisolated static let thumbnailPixels: CGFloat = 400

    struct Look: Equatable, Sendable {
        var preset: DivePreset = .natural
        var intensity: Float = 0.8
        /// Custom renders at the default intensity, so two Custom looks match whatever their intensity.
        static func == (a: Self, b: Self) -> Bool { a.preset == b.preset && (a.preset == .custom || a.intensity == b.intensity) }
    }
    enum State: Equatable { case loading, ready, failed, saved, saveFailed }
    struct Item: Identifiable {
        let id = UUID()
        let url: URL
        var originalName: String?
        var analysis: WaterAnalysis?
        var original: CGImage?
        var corrected: CGImage?
        var override: Look?
        var state = State.loading
        /// The last thumbnail render failed, so `corrected` no longer matches the look that will be saved.
        var previewFailed = false
    }

    let id = UUID()
    let diagnostics: DiagnosticRecorder
    let photos: PhotoProcessor
    var items: [Item]
    var shared = Look()
    private let adjustmentStore: CustomAdjustmentsStore
    /// The saved Custom sliders, shared with the editor. Written back on every change.
    var adjustments: CustomAdjustments { didSet { if adjustments != oldValue { adjustmentStore.save(adjustments) } } }
    private let formatStore: PhotoFormatStore
    /// The saved photo format, shared with the editor. Written back on every change.
    var format: ExportOptions.PhotoFormat { didSet { if format != oldValue { formatStore.save(format) } } }
    var comparing = false
    var saving = false
    var savedCount = 0
    var summary: String?
    /// Set when a batch saved every photo with no interruption: closing the summary may ask for a rating.
    var offersReview = false
    var error: String?
    var showPro = false
    /// Why the Pro screen opened from Save All, for example the wait for the next free photo.
    var proReason: String?
    var saveTask: Task<Void, Never>?
    private var interruption: String?
    private var backgroundTask = BackgroundTask()

    init(media: [ImportedMedia], diagnostics: DiagnosticRecorder, adjustmentStore: CustomAdjustmentsStore = .init(),
         formatStore: PhotoFormatStore = .init()) {
        self.diagnostics = diagnostics
        self.adjustmentStore = adjustmentStore
        adjustments = adjustmentStore.load()
        self.formatStore = formatStore
        format = formatStore.load()
        photos = PhotoProcessor(diagnostics: diagnostics)
        items = media.map { Item(url: $0.url, originalName: $0.originalName) }
    }
    convenience init(urls: [URL], diagnostics: DiagnosticRecorder, adjustmentStore: CustomAdjustmentsStore = .init(),
                     formatStore: PhotoFormatStore = .init()) {
        self.init(media: urls.map { ImportedMedia(url: $0, kind: .photo) }, diagnostics: diagnostics,
                  adjustmentStore: adjustmentStore, formatStore: formatStore)
    }

    /// Photos that can still be saved. Saved photos drop out, so a second Save All has nothing stale to report.
    var pendingCount: Int { items.filter { $0.analysis != nil && $0.state != .saved }.count }
    /// Fixed when a save starts, so progress does not shrink as photos finish.
    private(set) var saveTotal = 0
    func look(for item: Item) -> Look { item.override ?? shared }
    func settings(for item: Item) -> FilterSettings {
        let look = look(for: item)
        return FilterSettings(preset: look.preset, intensity: look.intensity, analysis: item.analysis ?? .neutral,
                              adjustments: look.preset == .custom ? adjustments : .zero)
    }

    /// Analyses one photo at a time, so peak memory does not grow with the selection size.
    func load() async {
        for index in items.indices where items[index].analysis == nil {
            let url = items[index].url
            do {
                let analysis = try await photos.analyze(url)
                items[index].analysis = analysis
            } catch is CancellationError { return } catch {
                items[index].state = .failed
                await record(error, operation: .inspection)
                continue
            }
            do {
                items[index].original = try await photos.preview(url, settings: .init(), original: true, maxPixel: Self.thumbnailPixels)
                items[index].corrected = try await photos.preview(url, settings: settings(for: items[index]),
                                                                  original: false, maxPixel: Self.thumbnailPixels)
            } catch is CancellationError { return } catch {
                // Analysis succeeded, so the photo can still be saved; only its thumbnail is missing.
                items[index].previewFailed = true
                await record(error, operation: .preview)
            }
            items[index].state = .ready
        }
    }

    /// Re-renders thumbnails that follow the shared look or use Custom (the sliders are shared), or only the given photo.
    func refreshThumbnails(only id: Item.ID? = nil) async {
        for index in items.indices where items[index].analysis != nil {
            if let id, items[index].id != id { continue }
            if id == nil, let override = items[index].override, override.preset != .custom { continue }
            do {
                let image = try await photos.preview(items[index].url, settings: settings(for: items[index]),
                                                     original: false, maxPixel: Self.thumbnailPixels)
                try Task.checkCancellation()
                items[index].corrected = image
                items[index].previewFailed = false
            } catch is CancellationError { return } catch {
                // Never keep showing the previous look: Save All would export a different one.
                items[index].corrected = nil
                items[index].previewFailed = true
                await record(error, operation: .preview)
            }
        }
    }

    func setOverride(_ look: Look?, for id: Item.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].override = look == shared ? nil : look
    }

    /// Pro saves every photo. Without Pro, Save All runs as the free trial when the photos fit its allowance
    /// (3 welcome photos in one run, Jake 4 Nov 2026): SDR with the watermark, one free photo per saved photo.
    func saveAll(purchases: PurchaseStore, trial: TrialStore) {
        guard !saving else { return }
        guard pendingCount > 0 else { return }
        saving = true
        savedCount = 0
        saveTotal = pendingCount
        interruption = nil
        backgroundTask.begin("Finish batch save") { [weak self] in
            Task { @MainActor in self?.stop(because: String(localized: "Saving stopped because UnderBlue went into the background. Keep the app open and try again.")) }
        }
        saveTask = Task {
            defer {
                saving = false; saveTask = nil
                backgroundTask.end()
            }
            await purchases.refreshEntitlement()
            let free = !purchases.isPro
            let targets = items.indices.filter { items[$0].analysis != nil && items[$0].state != .saved }
            if free, targets.count > trial.allowance(.photo) {
                proReason = trial.waitReason(.photo); showPro = true; return
            }
            // Ask for Photos access before any render. Without it every photo rendered and then failed to save
            // (flow review 6.5, Jake 4 Nov 2026). The alert names Settings.
            do { try await PhotoLibrarySaver.requireAddAccess() } catch { await record(error, operation: .save); return }
            if free {
                do { try trial.reserve([.photo: targets.count]) } catch { await record(error, operation: .save); return }
            }
            let format = format
            var failed = 0
            for index in targets {
                if Task.isCancelled { break }
                let output: URL
                do {
                    try StorageCheck.require(bytes: 100_000_000)
                    // Batch has no SDR/HDR choice: HDR photos stay HDR, SDR photos stay SDR. Free exports are SDR with the mark.
                    output = try await photos.export(items[index].url, settings: settings(for: items[index]), keepHDR: !free,
                                                     format: format, watermark: free)
                } catch is CancellationError { break } catch {
                    items[index].state = .saveFailed; failed += 1
                    await record(error, operation: .export)
                    continue
                }
                defer { TemporaryFiles.remove(output) }
                do {
                    try Task.checkCancellation()
                    let name = ExportNaming.fileName(source: items[index].originalName, preset: look(for: items[index]).preset,
                                                     extension: output.pathExtension)
                    try await PhotoLibrarySaver().save(output, kind: .photo, fileName: name)
                    items[index].state = .saved
                    savedCount += 1
                } catch is CancellationError { break } catch {
                    items[index].state = .saveFailed; failed += 1
                    await record(error, operation: .save)
                    // Access was turned off during the run. The rest would render and fail the same way.
                    if Failure.classify(error, operation: .save).kind == .permission { break }
                }
            }
            if free {
                do { if savedCount > 0 { try trial.commit([.photo: savedCount]) } else { try trial.rollback() } }
                catch { await record(error, operation: .save) }
            }
            ReviewPrompt().recordSaves(savedCount)
            offersReview = !targets.isEmpty && savedCount == targets.count && interruption == nil
            summary = Self.summaryText(saved: savedCount, total: items.count, saveFailed: failed,
                                       unopened: items.filter { $0.state == .failed }.count,
                                       left: targets.count - savedCount - failed, stop: interruption)
        }
    }

    /// The summary after Save All (flow review 6.9, Jake 4 Nov 2026). Every selected photo counts, including ones
    /// that never opened, so partial success never reads as full. Save failures have their own line. `stop` says
    /// why the run ended early; it shows only when photos were left, so a late Cancel does not mark a full run.
    static func summaryText(saved: Int, total: Int, saveFailed: Int, unopened: Int, left: Int, stop: String?) -> String {
        var parts = [saved == total && saveFailed == 0
            ? String(localized: "Saved to Photos: \(saved)")
            : String(localized: "Saved to Photos: \(saved) of \(total)")]
        if saveFailed > 0 { parts.append(String(localized: "Couldn’t save: \(saveFailed)")) }
        if unopened > 0 { parts.append(String(localized: "Couldn’t open: \(unopened)")) }
        if left > 0, let stop { parts.append(stop) }
        return parts.joined(separator: "\n")
    }
    /// The Cancel button while saving.
    func cancelSave() { stop(because: String(localized: "Cancelled")) }
    /// Ends Save All early and keeps the first reason for the summary.
    private func stop(because reason: String) {
        guard saving else { return }
        if interruption == nil { interruption = reason }
        saveTask?.cancel()
    }

    func memoryWarning() {
        let failure = Failure(kind: .memoryPressure, domain: "UnderBlue", code: 0)
        Task { await diagnostics.record(failure, operation: .export) }
        stop(because: failure.message)
    }

    func recordPreviewFailure(_ error: Error) async { await record(error, operation: .preview) }

    func close() {
        saveTask?.cancel()
        for item in items {
            TemporaryFiles.remove(item.url)
            let url = item.url, photos = photos
            Task { await photos.forget(url) }
        }
    }

    private func record(_ error: Error, operation: Operation) async {
        let failure = Failure.classify(error, operation: operation)
        guard failure.kind != .cancelled else { return }
        await diagnostics.record(failure, operation: operation)
        if self.error == nil, operation == .save || operation == .export { self.error = failure.message }
    }
}
