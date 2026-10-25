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
    /// Original closes the picker, as Done does, so both sides compare without the lines.
    var showingOriginal = false {
        didSet {
            guard showingOriginal != oldValue else { return }
            if showingOriginal { finishSubjectPicking() }
            compareChanged()
        }
    }
    private(set) var originalImage: CGImage?
    private(set) var correctedImage: CGImage?
    private(set) var player: AVPlayer?
    private(set) var previewBusy = false
    /// True while a redraw after a look or subject change runs. The newest redraw owns it.
    private(set) var previewRendering = false
    private var renderToken = 0
    private(set) var previewError: String?

    var selectedItem: BatchEngine.Item? { engine.items.first { $0.id == selection } }

    // MARK: Subjects
    /// The subject picker state of each queue item. An item without an entry is Auto. Only a picked item changes.
    private(set) var subjectStates: [BatchEngine.Item.ID: SubjectSelection] = [:]
    var subjects: SubjectSelection { selection.flatMap { subjectStates[$0] } ?? SubjectSelection() }
    /// The "Pick subjects manually" switch. Saved on the device, off by default.
    /// Turning it off returns every queue item to Auto.
    var subjectPickerEnabled: Bool {
        didSet {
            guard subjectPickerEnabled != oldValue else { return }
            subjectStore.save(subjectPickerEnabled)
            if subjectPickerEnabled { PreciseModelLoader.shared.start() }
            subjectSwitchChanged()
        }
    }
    private let subjectStore = SubjectPickerStore()
    /// The picker works on a queued photo and only while no batch runs.
    var canPickSubjects: Bool { selectedItem?.kind == .photo && !engine.running }

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
        subjectPickerEnabled = subjectStore.load()
        var limits = BatchEngine.Limits()
        limits.photoExport = parallel
        engine = BatchEngine(limits: limits, sink: DirectorySink(directory: FileManager.default.temporaryDirectory), diagnostics: recorder)
        engine.preferHDR = preferHDR
        folderURL = resolveBookmark()
        TemporaryFiles.cleanPreviousSession()
        if subjectPickerEnabled { PreciseModelLoader.shared.start() }
        #if DEBUG
        applyDemoArguments()
        #endif
    }

    #if DEBUG
    /// Launch arguments for screenshots and UI checks. They do not exist in a Release build.
    /// `--ui-demo-folder <path>` queues a folder, `--ui-demo-output <path>` sets the output folder,
    /// `--ui-demo-pro` lets Start run without a purchase, and `--ui-demo-start` presses Start.
    /// `--ui-demo-subjects manual` opens Manual on the selected photo, `--ui-demo-press x,y` clicks there (0...1 from
    /// the top left) and `--ui-demo-strength <0...1.5>` sets the subject strength (docs/ManualSubject.md).
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
                if value("--ui-demo-subjects") == "manual" {
                    // The press needs the precise model. Wait for the loader, at most 60 s.
                    for _ in 0..<1200 where !PreciseModelLoader.shared.isReady { try? await Task.sleep(for: .milliseconds(50)) }
                    chooseManualSubjects()
                    let xy = value("--ui-demo-press")?.split(separator: ",").compactMap { Double($0) } ?? []
                    if xy.count == 2 {
                        pressSubject(at: CGPoint(x: xy[0], y: xy[1]))
                        while subjects.pressing != nil { try? await Task.sleep(for: .milliseconds(50)) }
                    }
                    if let strength = value("--ui-demo-strength").flatMap(Float.init) { setSubjectStrength(strength) }
                }
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
        photoAnalysis[id] = nil; videoAnalysis[id] = nil; subjectStates[id] = nil
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

    /// Set when the biggest video in the queue needs more free memory than there is now. The window asks the user
    /// to close other apps and click "Check again". Nothing is shown when enough memory is free.
    var memoryShortage: VideoExporter.MemoryShortage?

    /// The shortage for the biggest video output in `pending`, or nil. A file that can't be read is left to the run.
    private func videoMemoryShortage(for pending: [BatchEngine.Item]) async -> VideoExporter.MemoryShortage? {
        var options = ExportOptions()
        if !isProOrDemo { options.resolution = .hd }
        var largest: CGSize?
        for item in pending where item.kind == .video {
            guard let metadata = try? await MediaInspector().inspect(item.url) else { continue }
            let size = options.size(for: metadata.displaySize)
            if largest.map({ size.width * size.height > $0.width * $0.height }) ?? true { largest = size }
        }
        return largest.flatMap { VideoExporter.memoryShortage(outputSize: $0) }
    }

    /// Pro runs the whole queue. Without Pro, one item may run as the free trial; more than one needs Pro.
    func start() {
        guard canStart, runTask == nil else { return }
        let photos = engine.items.contains { $0.kind == .photo && ($0.state == .queued || $0.state == .cancelled) }
        if photos, subjectPickerEnabled, !runWithoutEmphasis, !PreciseModelLoader.shared.isReady {
            modelNotReadyForStart = true
            PreciseModelLoader.shared.start()
            return
        }
        runTask = Task {
            defer { runTask = nil }
            await purchases.refreshEntitlement()
            let pending = engine.items.filter { $0.state == .queued || $0.state == .cancelled }
            if let shortage = await videoMemoryShortage(for: pending) { memoryShortage = shortage; return }
            memoryShortage = nil
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
            syncSubjectsToEngine()
            engine.start(settings: settings, photoFormat: format, trial: trialKind != nil)
            let ticker = Task { while !Task.isCancelled { updateDock(); try? await Task.sleep(for: .milliseconds(500)) } }
            await engine.waitUntilFinished()
            ticker.cancel()
            NSApp.dockTile.badgeLabel = nil
            if let trialKind { finishTrial(trialKind) }
            announceFinished()
            if runWithoutEmphasis { runWithoutEmphasis = false; syncSubjectsToEngine() }
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
        renderToken += 1
        let token = renderToken
        previewRendering = true
        previewTask = Task {
            defer { if token == renderToken { previewRendering = false } }
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

    // MARK: Subject picking

    /// Semi-auto: finds the subject groups once, then shows the picker. A photo with none stays in Auto.
    func chooseSemiAutoSubjects() {
        guard canPickSubjects, let item = selectedItem else { return }
        var state = subjectStates[item.id] ?? SubjectSelection()
        guard !state.isDetecting else { return }
        if state.candidates != nil { state.resumeSemiAuto(); applySubjects(state, to: item); return }
        state.startDetecting()
        subjectStates[item.id] = state
        Task {
            var done = subjectStates[item.id] ?? SubjectSelection()
            do {
                let found = try await previewPhotos.subjectCandidates(item.url)
                done.finishDetecting(found)
                // The outline of tiers two and three is a hint. Without it the picker still works.
                done.setTiers(try? await previewPhotos.subjectTiers(item.url))
            }
            catch is CancellationError { done.useAuto() }
            catch SubjectModelError.notReady { done.waitForModel(); PreciseModelLoader.shared.recheck() }
            catch { done.finishDetecting(nil); previewError = Failure.classify(error, operation: .preview).message }
            applySubjects(done, to: item)
        }
    }
    func chooseAutoSubjects() { change { $0.useAuto() } }
    /// Manual: no detection. A click on a subject picks it (docs/ManualSubject.md).
    func chooseManualSubjects() {
        guard canPickSubjects, let item = selectedItem else { return }
        var state = subjectStates[item.id] ?? SubjectSelection()
        state.useManual()
        applySubjects(state, to: item)
    }
    /// A click in Manual: on a picked subject it removes that subject, elsewhere it adds the subject under the point.
    func pressSubject(at point: CGPoint) {
        guard canPickSubjects, let item = selectedItem, var state = subjectStates[item.id], state.isManual, state.pressing == nil else { return }
        if let index = state.press(at: point) { state.removePress(index); applySubjects(state, to: item); return }
        state.startPress(at: point)
        subjectStates[item.id] = state
        Task {
            var done = subjectStates[item.id] ?? state
            do { done.finishPress(try await previewPhotos.pressMask(item.url, at: point)) }
            catch SubjectModelError.notReady { done.cancelPress(); PreciseModelLoader.shared.recheck() }
            catch { done.cancelPress(); if !(error is CancellationError) { previewError = Failure.classify(error, operation: .preview).message } }
            applySubjects(done, to: item)
        }
    }
    func removeSubjectPress(_ index: Int) { change { $0.removePress(index) } }
    func setSubjectStrength(_ value: Float) { change { $0.setStrength(value) } }
    func toggleSubject(_ id: Int) { change { $0.toggle(id) } }
    func toggleTier(_ id: Int) { change { $0.toggleTier(id) } }
    func finishSubjectPicking() { change { $0.done() } }
    func editSubjects() { change { $0.edit() } }
    func resetSubjects() { change { $0.reset() } }

    /// What an item's preview and export receive. With the Labs switch off there is no lift. With it on,
    /// an item without picks gets the lift on its automatic subjects, in the preview and the export alike.
    func subjectChoice(for id: BatchEngine.Item.ID) -> SubjectChoice {
        subjectPickerEnabled && !runWithoutEmphasis ? (subjectStates[id]?.choice ?? .auto) : .off
    }

    /// Set when Start waits for the precise model. Jake (24 Oct 2026): with Labs on, a photo is not saved
    /// before the model is ready. The way out is one run without subject emphasis.
    var modelNotReadyForStart = false
    private var runWithoutEmphasis = false
    func startWithoutEmphasis() {
        modelNotReadyForStart = false
        runWithoutEmphasis = true
        start()
    }

    /// Off returns every item to Auto and removes the lift. On or off, the preview redraws.
    private func subjectSwitchChanged() {
        if !subjectPickerEnabled {
            for id in Array(subjectStates.keys) {
                guard var state = subjectStates[id] else { continue }
                state.useAuto()
                subjectStates[id] = state
            }
        }
        syncSubjectsToEngine()
        if selectedItem?.kind == .photo, !showingOriginal { refreshPreview() }
    }

    /// Gives every queue item its current choice. A running batch refuses changes, so this runs before a start too.
    private func syncSubjectsToEngine() {
        for item in engine.items where item.kind == .photo { engine.setSubjects(item.id, subjectChoice(for: item.id)) }
    }

    /// The precise model arrived: redraw with the lift, and open the picker if the user was waiting for it.
    func preciseModelReady() {
        guard subjectPickerEnabled, let item = selectedItem, item.kind == .photo else { return }
        if subjectStates[item.id]?.status == .waitingForModel { chooseSemiAutoSubjects() }
        if !showingOriginal { refreshPreview() }
    }

    private func change(_ edit: (inout SubjectSelection) -> Void) {
        guard canPickSubjects, let item = selectedItem, var state = subjectStates[item.id] else { return }
        edit(&state)
        applySubjects(state, to: item)
    }

    /// Stores the state, gives the queue item its choice for export, and redraws the preview when the result changed.
    private func applySubjects(_ state: SubjectSelection, to item: BatchEngine.Item) {
        let changed = subjectStates[item.id]?.key != state.key
        subjectStates[item.id] = state
        engine.setSubjects(item.id, subjectChoice(for: item.id))
        if changed, selection == item.id, !showingOriginal { refreshPreview() }
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
        let image = try await previewPhotos.preview(item.url, settings: s, original: false, maxPixel: 1600,
                                                    subjects: subjectChoice(for: item.id))
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
