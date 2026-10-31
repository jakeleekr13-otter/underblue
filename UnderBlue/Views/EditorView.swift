import SwiftUI
import AVKit
import StoreKit

struct EditorView: View {
    @Environment(PurchaseStore.self) private var purchases
    @Environment(TrialStore.self) private var trial
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    @Environment(\.horizontalSizeClass) private var widthClass
    @State private var model: EditorModel
    @State private var zoom = PreviewZoom()
    init(media: ImportedMedia, diagnostics: DiagnosticRecorder) { _model = State(initialValue: EditorModel(media: media, diagnostics: diagnostics)) }
    var body: some View {
        @Bindable var model = model
        GeometryReader { geometry in
            // Size changes (rotation, fold, unfold) only swap the container; model and zoom live above it and stay.
            if let fold = Self.foldSplit(in: geometry) {
                foldedLayout(fold, height: geometry.size.height)
            } else if Self.usesSidePanel(geometry.size, regularWidth: widthClass == .regular) {
                HStack(spacing: 16) {
                    previewPanel
                    paneControls(minHeight: geometry.size.height, grid: widthClass == .regular).frame(width: min(330, geometry.size.width * 0.42))
                }
            } else {
                VStack(spacing: 16) {
                    previewPanel
                    // The controls ask for their height first. Without this the preview and the controls split the space in half and Export is cut off.
                    ScrollView { controls() }.frame(maxHeight: min(350, geometry.size.height * 0.55)).layoutPriority(1)
                }
            }
        }.disabled(model.exporting).padding(.bottom, 8)
            .navigationTitle("Edit").navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(model.exporting)
            .task { await model.load() }
            .task(id: model.settings) { if !model.loading { await model.refreshPreview() } }
            .task(id: model.comparing) { if !model.loading { await model.refreshPreview() } }
            .task(id: model.subjects.key) { if !model.loading { await model.refreshPreview() } }
            .task(id: PreciseModelLoader.shared.isReady) { if PreciseModelLoader.shared.isReady { await model.preciseModelReady() } }
            .onDisappear { model.close() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in model.memoryWarning() }
            .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)) { model.playbackFailed($0) }
            .onChange(of: scenePhase) { _, phase in model.scenePhaseChanged(phase) }
            .sheet(isPresented: $model.showPro) { ProView() }
            .sheet(isPresented: $model.showExportOptions, onDismiss: { model.optionsDismissing = false }) { ExportView(model: model) }
            .sheet(isPresented: Binding(get: { model.completedURL != nil && !model.optionsDismissing }, set: { if !$0 { model.discardCompleted() } })) {
                ExportCompleteView(model: model)
            }
            .overlay { if model.exporting { exportProgress } }
            .alert("Couldn’t finish", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
            .alert("UnderBlue", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
                Button("OK") {
                    model.notice = nil
                    if model.offersReview { model.offersReview = false; Task { await ReviewPrompt().askIfDue(requestReview) } }
                }
            } message: { Text(model.notice ?? "") }
            .alert("Subject model not ready", isPresented: $model.modelNotReadyForSave) {
                Button("Export without subject emphasis") { Task { await model.saveAnywayWithoutEmphasis(purchases: purchases, trial: trial) } }
                if PreciseModelLoader.shared.state == .failed { Button("Try again") { PreciseModelLoader.shared.start() } }
                Button("Wait", role: .cancel) { }
            } message: { Text(SubjectPickerText.modelWait(PreciseModelLoader.shared.state)) }
    }
    /// Landscape always gets the side panel. A regular-width screen close to square (an unfolded foldable)
    /// gets it too, because a bottom panel would leave the preview a short, wide strip.
    nonisolated static let squareAspect: CGFloat = 0.85
    nonisolated static func usesSidePanel(_ size: CGSize, regularWidth: Bool) -> Bool {
        size.width > size.height || (regularWidth && size.width >= size.height * squareAspect)
    }
    /// Where a partly folded screen splits. `nil` when nothing is folded, or before iOS 27.1.
    static func foldSplit(in geometry: GeometryProxy) -> FoldSplit? {
        guard #available(iOS 27.1, *) else { return nil }
        let fold = geometry.reservedRegions(kind: .division).first { $0.isActive }
        return fold.flatMap { FoldSplit(division: $0.frame, in: geometry.size) }
    }
    /// Preview on the first pane, controls on the second, nothing on the fold itself.
    private func foldedLayout(_ fold: FoldSplit, height: CGFloat) -> some View {
        FoldPanes(fold: fold, height: height, first: previewPanel) { paneControls(minHeight: $0, grid: fold.axis == .horizontal) }
    }
    /// A short control stack sits in the middle of its pane. A tall one scrolls.
    /// `grid` is for a narrow pane. A wide pane keeps the sideways row, which leaves room for Export.
    private func paneControls(minHeight: CGFloat, grid: Bool) -> some View {
        ScrollView { controls(presetGrid: grid).frame(maxWidth: .infinity, minHeight: minHeight, alignment: .center) }
    }
    private var previewPanel: some View {
        ZStack {
            Color.black
            if model.media.kind == .video {
                // No playback while the scene is analysed: the filter-only preview stutters on large clips.
                VideoPlayer(player: model.player).disabled(model.analyzing).allowsHitTesting(!model.analyzing)
            }
            else if let preview = model.comparing ? model.originalPreview : model.preview {
                // Compare swaps the image but keeps the zoom, so the same detail can be checked both ways.
                // The picker shows over the corrected image only. Compare hides it.
                let picking = model.subjects.showsOverlay && !model.comparing
                let holding: ((CGPoint) -> Void)? = picking && model.subjects.isManual
                    ? { point in Task { await model.pressSubject(at: point) } } : nil
                ZoomablePreview(image: preview, zoom: $zoom, overlayActive: picking, onZoomIn: { model.requestDetailPreview() },
                                onHold: holding) { size in
                    if picking, model.subjects.isManual {
                        let pressed = model.subjects.pressed ?? .empty
                        SubjectPicker(candidates: pressed, picks: Set(pressed.groups.map(\.id)), size: size, zoom: zoom.scale,
                                      pressMode: true, pressing: model.subjects.pressing) { model.removeSubjectPress($0) }
                    } else if picking, let candidates = model.subjects.candidates {
                        SubjectPicker(candidates: candidates, picks: model.subjects.picks, tiers: model.subjects.tiers, tierPieces: model.subjects.tierPieces,
                                          tierDrawing: model.subjects.tierDrawing, tiersOff: model.subjects.tiersOff,
                                          size: size, zoom: zoom.scale, onToggleTier: { model.toggleTier($0) }) { model.toggleSubject($0) }
                    }
                }
                .overlay(alignment: .topTrailing) { PreviewRenderingIndicator(active: model.previewRendering) }
            }
            if model.loading {
                if model.analyzing { VStack(spacing: 12) { longVideoNotice; ProgressView("Analyzing…") } }
                else { ProgressView("Opening…") }
            } else if model.analyzing {
                // Playback is blocked until the scene is analysed. The colour is then final from the first frame.
                VStack(spacing: 8) {
                    longVideoNotice
                    HStack(spacing: 8) { ProgressView(); Text("Analyzing…").font(.footnote.weight(.medium)) }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .accessibilityElement(children: .combine)
                }.frame(maxHeight: .infinity, alignment: .top).padding(.top, 12)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
    }
    @ViewBuilder private var longVideoNotice: some View {
        if model.isLongVideo {
            Text("Analysis and correction can take longer for longer videos.")
                .font(.footnote).multilineTextAlignment(.center)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
        }
    }
    private func controls(presetGrid: Bool = false) -> some View {
        @Bindable var model = model
        return VStack(spacing: 18) {
            if model.previewPaused { Button("Retry preview") { Task { await model.retryPreview() } } }
            if model.metadata?.isHDR == true || (model.media.kind == .photo && model.capability.hdrAvailable) { Text("HDR source · SDR preview").font(.caption).foregroundStyle(.secondary) }
            HStack {
                // The buttons never wrap; the preset name gives way first on narrow screens.
                Text(model.comparing ? String(localized: "Original") : model.settings.preset.localizedName).font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                if model.media.kind == .video {
                    Button { if model.clipPlaying { model.stopClip(rewind: true) } else { Task { await model.playClip() } } } label: {
                        Label(model.clipPlaying ? "Stop" : "3s Preview", systemImage: model.clipPlaying ? "stop.fill" : "play.fill")
                            .lineLimit(1).fixedSize()
                    }.buttonStyle(.bordered).frame(minHeight: 44).disabled(!model.ready || model.analyzing)
                        .accessibilityHint("Play three seconds from the current position, then return")
                }
                Button {
                    // Compare closes the picker, as Done does, so both sides compare without the lines.
                    if !model.comparing { model.finishSubjectPicking() }
                    model.comparing.toggle()
                } label: {
                    Label("Compare", systemImage: model.comparing ? "eye.fill" : "eye").lineLimit(1).fixedSize()
                }
                    .buttonStyle(.bordered).frame(minHeight: 44)
                    .accessibilityValue(model.comparing ? "Original" : "Corrected")
                    .accessibilityHint("Show original media without correction")
            }.padding(.horizontal)
            presetPicker(grid: presetGrid)
            if model.media.kind == .photo, model.subjectPickerEnabled { subjectsRow }
            if model.settings.preset == .custom {
                // Custom has no intensity: it renders at the default intensity (0.8) and has its own sliders.
                CustomAdjustmentControls(adjustments: $model.settings.adjustments).padding(.horizontal)
            } else {
                VStack {
                    HStack { Text("Intensity"); Spacer(); Text(model.settings.intensity, format: .percent.precision(.fractionLength(0))).monospacedDigit() }
                    Slider(value: $model.settings.intensity, in: 0...1).accessibilityLabel("Filter intensity")
                        .disabled(model.settings.preset == .original)
                }.padding(.horizontal)
            }
            Button("Export") { Task { await model.requestExport(purchases: purchases, trial: trial) } }
                .buttonStyle(.borderedProminent).frame(minHeight: 44).disabled(!model.ready || model.exporting || model.analyzing)
        }.padding(.bottom, 8)
    }
    /// Shown only when the Labs switch in Help is on (SubjectPickerStore): the Auto, Semi-auto or Manual bar,
    /// then Done and Reset while picking, and the subject strength once something is picked.
    /// Semi-auto says so when Vision finds nothing.
    private var subjectsRow: some View {
        subjectsBar(model.subjects).padding(.horizontal)
    }
    private func subjectsBar(_ subjects: SubjectSelection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Subjects").font(.subheadline)
                Spacer(minLength: 8)
                Picker("Subjects", selection: Binding(
                    get: { subjects.mode },
                    set: { mode in
                        switch mode {
                        case .auto: model.chooseAutoSubjects()
                        case .semiAuto: Task { await model.chooseSemiAutoSubjects() }
                        case .manual: model.chooseManualSubjects()
                        }
                    })) {
                    Text("Auto").tag(SubjectSelection.Mode.auto)
                    Text("Semi-auto").tag(SubjectSelection.Mode.semiAuto)
                    Text("Manual").tag(SubjectSelection.Mode.manual)
                }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 260).disabled(subjects.isDetecting || subjects.pressing != nil)
                    .accessibilityLabel("Subjects")
            }
            if subjects.mode != .auto {
                HStack {
                    if subjects.showsOverlay {
                        Button("Done") { model.finishSubjectPicking() }
                    } else {
                        Button { model.editSubjects() } label: { Label("Edit", systemImage: "pencil") }
                    }
                    Button("Reset") { model.resetSubjects() }
                }.buttonStyle(.bordered).frame(minHeight: 44)
            }
            if subjects.showsStrength { SubjectStrengthSlider(strength: subjects.strength) { model.setSubjectStrength($0) } }
            Text(SubjectPickerText.summary(subjects)).font(.footnote).foregroundStyle(.secondary)
            if let legend = SubjectPickerText.legend(subjects) { Text(legend).font(.footnote).foregroundStyle(.secondary) }
            if let notice = SubjectPickerText.notice(subjects) { Text(notice).font(.footnote).foregroundStyle(.orange) }
        }.animation(.default, value: subjects.status)
    }
    /// One row that scrolls sideways, or a two-column grid when the pane is narrow and tall.
    @ViewBuilder private func presetPicker(grid: Bool) -> some View {
        if grid {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(DivePreset.allCases) { presetButton($0, fill: true) }
            }.padding(.horizontal)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) { ForEach(DivePreset.allCases) { presetButton($0, fill: false) } }.padding(.horizontal)
            }
        }
    }
    private func presetButton(_ preset: DivePreset, fill: Bool) -> some View {
        Button { model.settings.preset = preset } label: {
            VStack(spacing: 8) {
                Image(systemName: preset.symbolName).font(.title2)
                Text(preset.localizedName).font(.caption.weight(.medium))
            }.frame(minWidth: fill ? 0 : 96, maxWidth: fill ? .infinity : nil, minHeight: 72).padding(.horizontal, 5)
                .background(model.settings.preset == preset ? Color.mint.opacity(0.2) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(model.settings.preset == preset ? Color.mint : .clear))
        }.buttonStyle(.plain).accessibilityAddTraits(model.settings.preset == preset ? .isSelected : [])
    }
    private var exportProgress: some View {
        VStack(spacing: 20) {
            if model.media.kind == .video {
                ProgressView(value: model.progress).frame(width: 220)
                Text(model.progress >= 0.99
                     ? String(localized: "Checking your video…")
                     : String(localized: "Exporting \(Int(model.progress * 100))%"))
                if model.isLongVideo {
                    Text("Analysis and correction can take longer for longer videos.")
                        .font(.footnote).multilineTextAlignment(.center).frame(maxWidth: 240)
                }
            } else { ProgressView("Exporting…") }
            Text("Keep UnderBlue open until export finishes.").font(.footnote)
            Button("Cancel") { model.exportTask?.cancel() }.frame(minHeight: 44)
        }.padding(30).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

/// Two panes on either side of the fold, measured in the editor's own coordinates.
struct FoldSplit: Equatable {
    /// `.vertical` stacks the panes top to bottom (the fold line runs across); `.horizontal` puts them side by side.
    enum Axis { case vertical, horizontal }
    let axis: Axis
    let first: CGFloat
    let gap: CGFloat
    let second: CGFloat

    /// A pane under this size has no room for the controls, so the fold is ignored.
    static let minimumPane: CGFloat = 160

    init?(division: CGRect, in size: CGSize) {
        guard size.width > 0, size.height > 0, !division.isNull, !division.isEmpty else { return nil }
        let acrossFold = division.width >= division.height
        let length = acrossFold ? size.height : size.width
        let start = acrossFold ? division.minY : division.minX
        let end = acrossFold ? division.maxY : division.maxX
        let first = max(0, start), second = max(0, length - end)
        guard first >= Self.minimumPane, second >= Self.minimumPane else { return nil }
        self.axis = acrossFold ? .vertical : .horizontal
        self.first = first
        self.gap = length - first - second
        self.second = second
    }
}

/// The first pane, the fold gap, then the second pane, along the fold's axis.
/// `second` gets the pane's height, so a short stack can centre itself.
struct FoldPanes<First: View, Second: View>: View {
    let fold: FoldSplit
    /// Full height of the screen area. A side-by-side split gives each pane this height.
    let height: CGFloat
    let first: First
    let second: (CGFloat) -> Second

    var body: some View {
        switch fold.axis {
        case .vertical:
            VStack(spacing: 0) {
                first.frame(height: fold.first)
                Color.clear.frame(height: fold.gap)
                second(fold.second).frame(height: fold.second)
            }
        case .horizontal:
            HStack(spacing: 0) {
                first.frame(width: fold.first)
                Color.clear.frame(width: fold.gap)
                second(height).frame(width: fold.second)
            }
        }
    }
}
