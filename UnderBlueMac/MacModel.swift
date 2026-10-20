import AVFoundation
import AppKit
import SwiftUI
import UserNotifications

/// State of the Mac window: the queue (BatchEngine), the look, the output place and the preview of the selected item.
/// The look applies to every item. The Mac window has no per-item look.
@MainActor @Observable
final class MacModel {
    enum SaveTarget: String, CaseIterable, Identifiable, Sendable {
        case folder, photos
        var id: String { rawValue }
    }
    private enum Keys {
        static let saveTarget = "mac.saveTarget", folder = "mac.outputFolder.v1", hdr = "mac.preferHDR", parallel = "mac.parallelPhotos"
    }

    let diagnostics = DiagnosticsCenter()
    let purchases: PurchaseStore
    let trial: TrialStore
    let engine: BatchEngine
    private let adjustmentStore = CustomAdjustmentsStore()
    private let formatStore = PhotoFormatStore()
    private let defaults = UserDefaults.standard

    // MARK: Look and settings
    var preset: DivePreset = .natural { didSet { if preset != oldValue { lookChanged() } } }
    var intensity: Float = 0.8 { didSet { if intensity != oldValue { lookChanged() } } }
    var adjustments: CustomAdjustments {
        didSet { if adjustments != oldValue { adjustmentStore.save(adjustments); lookChanged() } }
    }
    var format: ExportOptions.PhotoFormat { didSet { formatStore.save(format) } }
    var preferHDR: Bool { didSet { defaults.set(preferHDR, forKey: Keys.hdr); engine.preferHDR = preferHDR } }
    /// Photos exported at the same time, 1 to 4. Applies from the next run.
    /// Do not assign to this property inside its own didSet: with @Observable that calls didSet again, without end.
    var parallelPhotos: Int {
        didSet {
            let clamped = min(4, max(1, parallelPhotos))
            defaults.set(clamped, forKey: Keys.parallel)
            engine.limits.photoExport = clamped
        }
    }
    var saveTarget: SaveTarget { didSet { defaults.set(saveTarget.rawValue, forKey: Keys.saveTarget) } }
    private(set) var folderURL: URL?

    // MARK: Window state
    var selection: BatchEngine.Item.ID? { didSet { if selection != oldValue { loadPreview() } } }
    var showPaywall = false
    var showImporter = false
    var paywallReason: String?
    var notice: String?
    var showingOriginal = false { didSet { if showingOriginal != oldValue { compareChanged() } } }
    private(set) var originalImage: CGImage?
    private(set) var correctedImage: CGImage?
    private(set) var player: AVPlayer?
    private(set) var previewBusy = false
    private(set) var previewError: String?

    var selectedItem: BatchEngine.Item? { engine.items.first { $0.id == selection } }

    // MARK: Private
    private let previewPhotos: PhotoProcessor
    private let videoPreview: VideoPreview
    private let previewSettings = PreviewSettings()
    private var photoAnalysis: [UUID: WaterAnalysis] = [:]
    private var videoAnalysis: [UUID: VideoRestorationAnalysis] = [:]
    private var previewTask: Task<Void, Never>?
    private var previewGeneration = PreviewGeneration()
    private var runTask: Task<Void, Never>?
    private var openedScopes: [URL] = []
    private var askedForNotifications = false
    private var importingShared = false

    init() {
        let recorder = diagnostics.recorder
        purchases = PurchaseStore(diagnostics: recorder)
        trial = TrialStore(persistence: KeychainTrialPersistence(), diagnostics: recorder)
        previewPhotos = PhotoProcessor(diagnostics: recorder)
        videoPreview = VideoPreview(diagnostics: recorder)
        adjustments = adjustmentStore.load()
        format = formatStore.load()
        preferHDR = defaults.object(forKey: Keys.hdr) as? Bool ?? true
        let parallel = min(4, max(1, defaults.object(forKey: Keys.parallel) as? Int ?? 1))
        parallelPhotos = parallel
        saveTarget = SaveTarget(rawValue: defaults.string(forKey: Keys.saveTarget) ?? "") ?? .folder
        var limits = BatchEngine.Limits()
        limits.photoExport = parallel
        engine = BatchEngine(limits: limits, sink: DirectorySink(directory: FileManager.default.temporaryDirectory), diagnostics: recorder)
        engine.preferHDR = preferHDR
        folderURL = resolveBookmark()
        TemporaryFiles.cleanPreviousSession()
        #if DEBUG
        applyDemoArguments()
        #endif
    }

    #if DEBUG
    /// Launch arguments for screenshots and UI checks. They do not exist in a Release build.
    /// `--ui-demo-folder <path>` queues a folder, `--ui-demo-output <path>` sets the output folder,
    /// `--ui-demo-pro` lets Start run without a purchase, and `--ui-demo-start` presses Start.
    private var demoPro = false
    private var demoNoPreview = false
    private func applyDemoArguments() {
        let arguments = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? { arguments.firstIndex(of: flag).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil } }
        demoPro = arguments.contains("--ui-demo-pro")
        demoNoPreview = arguments.contains("--ui-demo-nopreview")
        if let name = value("--ui-demo-preset"), let chosen = DivePreset.allCases.first(where: { $0.rawValue.lowercased() == name.lowercased() }) { preset = chosen }
        if let parallel = value("--ui-demo-parallel").flatMap(Int.init) { parallelPhotos = min(4, max(1, parallel)) }
        if let output = value("--ui-demo-output") { folderURL = URL(fileURLWithPath: output, isDirectory: true); saveTarget = .folder }
        if let folder = value("--ui-demo-folder") {
            Task {
                await add([URL(fileURLWithPath: folder, isDirectory: true)])
                if let name = value("--ui-demo-select") { selection = engine.items.first { $0.originalName == name }?.id }
                if arguments.contains("--ui-demo-start") { start() }
            }
        }
    }
    #endif

    var settings: FilterSettings {
        FilterSettings(preset: preset, intensity: intensity, analysis: .neutral,
                       adjustments: preset == .custom ? adjustments : .zero)
    }

    // MARK: Adding files

    func add(_ urls: [URL]) async {
        guard !urls.isEmpty, !engine.running else {
            if engine.running { notice = String(localized: "Wait for the batch to finish, or stop it, before adding files.") }
            return
        }
        for url in urls where url.startAccessingSecurityScopedResource() { openedScopes.append(url) }
        let result = await Task.detached(priority: .userInitiated) { MediaScanner.scan(urls) }.value
        let known = Set(engine.items.map { $0.url.standardizedFileURL.path })
        let fresh = result.media.filter { !known.contains($0.url.standardizedFileURL.path) }
        engine.add(fresh)
        if selection == nil, !isDemoNoPreview { selection = engine.items.first?.id }
        if fresh.isEmpty && result.skipped > 0 {
            notice = String(localized: "No photos or videos found in what you added.")
        } else if result.skipped > 0 {
            notice = String(localized: "Skipped \(result.skipped) files that are not photos or videos.")
        }
    }

    /// Adds the newest share from the Mac share menu. The share extension copies files into the App Group inbox
    /// and opens `underblue://share`. UnderBlue also looks when it becomes active, so a refused open is not lost.
    /// While a batch runs the share waits in the inbox for the next call. `takeShared` is replaceable for tests.
    func importShared(takeShared: () async -> (media: [ImportedMedia], failed: Int)? = { await FileImport.takeShared() }) async {
        guard !engine.running, !importingShared else { return }
        importingShared = true
        defer { importingShared = false }
        guard let shared = await takeShared() else { return }
        let known = Set(engine.items.map { $0.url.standardizedFileURL.path })
        let fresh = shared.media.filter { !known.contains($0.url.standardizedFileURL.path) }
        engine.add(fresh)
        if let first = fresh.first { selection = engine.items.first { $0.url == first.url }?.id }
        if fresh.isEmpty, shared.failed == 0 { return }
        notice = shared.failed == 0 ? String(localized: "Added \(fresh.count) from the share menu.")
            : String(localized: "Added \(fresh.count) from the share menu. Couldn’t add \(shared.failed).")
    }

    func remove(_ id: BatchEngine.Item.ID) {
        let url = engine.items.first { $0.id == id }?.url
        guard engine.remove(id) else { return }
        // Files that came from the share menu were moved into the temporary folder. Files you added stay where they are.
        TemporaryFiles.remove(url)
        photoAnalysis[id] = nil; videoAnalysis[id] = nil
        if selection == id { selection = engine.items.first?.id }
    }

    func clearFinished() {
        for item in engine.items where item.state == .done {
            let url = item.url
            if engine.remove(item.id) { TemporaryFiles.remove(url) }
        }
        if selectedItem == nil { selection = engine.items.first?.id }
    }

    // MARK: Output place

    func chooseFolder() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Choose the folder for corrected photos and videos.")
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(data, forKey: Keys.folder)
            folderURL = url
            return true
        } catch {
            notice = Failure.classify(error, operation: .save).message
            return false
        }
    }

    private func resolveBookmark() -> URL? {
        guard let data = defaults.data(forKey: Keys.folder) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(fresh, forKey: Keys.folder)
        }
        return url
    }

    /// Label for the action that shows the results: Finder for a folder, the Photos app for the library.
    var showResultsTitle: String {
        saveTarget == .photos ? String(localized: "Open Photos") : String(localized: "Show in Finder")
    }
    var canShowResults: Bool { saveTarget == .photos || folderURL != nil }

    /// Opens the output folder in Finder, or the Photos app. Results saved under an earlier target are not tracked.
    func showResults() {
        switch saveTarget {
        case .folder:
            if let folderURL { NSWorkspace.shared.open(folderURL) }
        case .photos:
            if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Photos") {
                NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
            }
        }
    }

    /// Selects one finished file in Finder. Falls back to the folder when the file is gone.
    func reveal(_ id: UUID) {
        guard saveTarget == .folder, let folderURL,
              let name = engine.items.first(where: { $0.id == id })?.savedName else { showResults(); return }
        let scoped = folderURL.startAccessingSecurityScopedResource()
        defer { if scoped { folderURL.stopAccessingSecurityScopedResource() } }
        let file = folderURL.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: file.path) {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } else {
            NSWorkspace.shared.open(folderURL)
        }
    }

    private func makeSink() -> BatchSink? {
        switch saveTarget {
        case .photos: return PhotosSink()
        case .folder:
            if folderURL == nil, !chooseFolder() { return nil }
            return folderURL.map { DirectorySink(directory: $0) }
        }
    }

    // MARK: Running

    private var isDemoNoPreview: Bool {
        #if DEBUG
        return demoNoPreview
        #else
        return false
        #endif
    }

    private var isProOrDemo: Bool {
        #if DEBUG
        return purchases.isPro || demoPro
        #else
        return purchases.isPro
        #endif
    }

    var canStart: Bool { !engine.running && engine.pendingCount > 0 }

    /// Pro runs the whole queue. Without Pro, one item may run as the free trial; more than one needs Pro.
    func start() {
        guard canStart, runTask == nil else { return }
        runTask = Task {
            defer { runTask = nil }
            await purchases.refreshEntitlement()
            let pending = engine.items.filter { $0.state == .queued || $0.state == .cancelled }
            var trialKind: ImportedMedia.Kind?
            if !isProOrDemo {
                guard pending.count == 1, let kind = pending.first?.kind else {
                    paywallReason = String(localized: "Batch needs UnderBlue Pro. The free trial corrects one photo and one short video."); showPaywall = true; return
                }
                guard trial.canExport(kind) else {
                    paywallReason = String(localized: "The free trial for this kind of file is used."); showPaywall = true; return
                }
                do { try trial.reserve(kind) } catch { notice = Failure.classify(error, operation: .trial).message; return }
                trialKind = kind
            }
            guard let sink = makeSink() else {
                if let trialKind { rollbackTrial(trialKind) }
                return
            }
            engine.sink = sink
            if !askedForNotifications {
                askedForNotifications = true
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            }
            engine.start(settings: settings, photoFormat: format, trial: trialKind != nil)
            let ticker = Task { while !Task.isCancelled { updateDock(); try? await Task.sleep(for: .milliseconds(500)) } }
            await engine.waitUntilFinished()
            ticker.cancel()
            NSApp.dockTile.badgeLabel = nil
            if let trialKind { finishTrial(trialKind) }
            announceFinished()
        }
    }

    func cancel() { engine.cancel() }

    func retryFailed() { engine.retryFailed() }

    private func finishTrial(_ kind: ImportedMedia.Kind) {
        let saved = engine.items.contains { $0.state == .done }
        do { if saved { try trial.commit(kind) } else { try trial.rollback() } }
        catch { notice = Failure.classify(error, operation: .trial).message }
    }
    private func rollbackTrial(_ kind: ImportedMedia.Kind) {
        do { try trial.rollback() } catch { notice = Failure.classify(error, operation: .trial).message }
    }

    private func updateDock() {
        let total = engine.items.count
        NSApp.dockTile.badgeLabel = engine.running ? "\(engine.doneCount)/\(total)" : nil
    }

    private func announceFinished() {
        let done = engine.doneCount, failed = engine.failedCount
        notice = failed == 0 ? String(localized: "Done: \(done) saved.") : String(localized: "Done: \(done) saved, \(failed) failed.")
        guard !NSApp.isActive else { return }
        let content = UNMutableNotificationContent()
        content.title = "UnderBlue"
        content.body = notice ?? ""
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // MARK: Preview

    private func lookChanged() { refreshPreview() }
    private func compareChanged() {
        guard let item = selectedItem, item.kind == .video else { return }
        refreshPreview()
    }

    private func clearPreview() {
        previewTask?.cancel()
        originalImage = nil; correctedImage = nil; player?.pause(); player = nil
        previewError = nil; previewBusy = false
    }

    private func loadPreview() {
        clearPreview()
        guard let item = selectedItem else { return }
        previewBusy = true
        previewTask = Task {
            defer { previewBusy = false }
            do {
                switch item.kind {
                case .photo: try await buildPhotoPreview(item)
                case .video: try await buildVideoPreview(item)
                }
            } catch is CancellationError {
            } catch {
                let failure = Failure.classify(error, operation: .preview)
                previewError = failure.message
                await diagnostics.recorder.record(failure, operation: .preview)
            }
        }
    }

    /// Redraws the corrected view after a look change. Rapid changes cancel the earlier draw.
    private func refreshPreview() {
        guard let item = selectedItem else { return }
        previewTask?.cancel()
        previewTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(60))
                switch item.kind {
                case .photo: try await renderCorrectedPhoto(item)
                case .video: try await renderVideoComposition(item)
                }
            } catch is CancellationError {
            } catch {
                previewError = Failure.classify(error, operation: .preview).message
            }
        }
    }

    private func buildPhotoPreview(_ item: BatchEngine.Item) async throws {
        let analysis = try await previewPhotos.analyze(item.url)
        photoAnalysis[item.id] = analysis
        var s = settings; s.analysis = analysis
        originalImage = try await previewPhotos.preview(item.url, settings: s, original: true, maxPixel: 1600)
        try Task.checkCancellation()
        try await renderCorrectedPhoto(item)
    }

    private func renderCorrectedPhoto(_ item: BatchEngine.Item) async throws {
        guard let analysis = photoAnalysis[item.id] else { return }
        var s = settings; s.analysis = analysis
        let image = try await previewPhotos.preview(item.url, settings: s, original: false, maxPixel: 1600)
        try Task.checkCancellation()
        correctedImage = image
        previewError = nil
    }

    private func buildVideoPreview(_ item: BatchEngine.Item) async throws {
        let url = item.url
        let metadata = try await SafeReadRetry().run(operation: .inspection) { try await MediaInspector().inspect(url) }
        previewSettings.update(settings, comparing: showingOriginal)
        let avItem = try await videoPreview.item(url, settings: previewSettings, analysis: videoAnalysis[item.id])
        try Task.checkCancellation()
        player = AVPlayer(playerItem: avItem)
        previewBusy = false
        // Scene analysis takes a while. The preview plays at once and improves when the analysis is ready.
        if videoAnalysis[item.id] == nil {
            do { videoAnalysis[item.id] = try await videoPreview.analyze(url, metadata: metadata) }
            catch is CancellationError { throw CancellationError() }
            catch { await diagnostics.recorder.record(Failure.restorationFallback(.videoSceneAnalysis), operation: .videoRestoration) }
        }
        try await renderVideoComposition(item)
    }

    private func renderVideoComposition(_ item: BatchEngine.Item) async throws {
        guard let avItem = player?.currentItem else { return }
        var s = settings
        if let analysis = videoAnalysis[item.id] { s.analysis = analysis.legacyAnalysis }
        previewSettings.update(s, comparing: showingOriginal)
        let generation = previewGeneration.begin()
        let composition = try await videoPreview.composition(asset: avItem.asset, settings: previewSettings, analysis: videoAnalysis[item.id])
        try Task.checkCancellation()
        guard previewGeneration.accepts(generation) else { return }
        avItem.videoComposition = composition
        if let player, player.rate == 0 { await player.seek(to: player.currentTime(), toleranceBefore: .zero, toleranceAfter: .zero) }
    }
}
