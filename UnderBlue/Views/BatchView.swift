import SwiftUI

struct BatchView: View {
    @Environment(PurchaseStore.self) private var purchases
    @State var model: BatchModel
    @State private var pressed: BatchModel.Item.ID?
    @State private var detail: BatchModel.Item.ID?
    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 6)]

    var body: some View {
        @Bindable var model = model
        GeometryReader { geometry in
            if let fold = EditorView.foldSplit(in: geometry) {
                // Partly folded: the grid on one side of the fold, the controls on the other.
                FoldPanes(fold: fold, height: geometry.size.height, first: grid) { paneHeight in
                    ScrollView { controls(presetGrid: fold.axis == .horizontal).frame(maxWidth: .infinity, minHeight: paneHeight, alignment: .center) }
                }
            } else {
                grid.safeAreaInset(edge: .bottom) { controls().background(.bar) }
            }
        }
        .navigationTitle(String(localized: "\(model.items.count) Photos")).navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.saving)
        .disabled(model.saving)
        .task { await model.load() }
        .task(id: ThumbnailKey(look: model.shared, adjustments: model.adjustments)) { await model.refreshThumbnails() }
        .onDisappear { model.close() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in model.memoryWarning() }
        .overlay { if model.saving { savingProgress } }
        .sheet(isPresented: $model.showPro) { ProView() }
        .fullScreenCover(item: Binding(get: { detail.map(DetailID.init) }, set: { detail = $0?.id })) { start in
            BatchDetailView(model: model, selection: start.id)
        }
        .alert("UnderBlue", isPresented: Binding(get: { model.summary != nil }, set: { if !$0 { model.summary = nil } })) {
            Button("OK") { model.summary = nil }
        } message: { Text(model.summary ?? "") }
        .alert("Couldn’t save", isPresented: Binding(get: { model.error != nil && !model.saving }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(model.items) { item in cell(item) }
            }.padding(.horizontal, 6)
        }
    }

    private func cell(_ item: BatchModel.Item) -> some View {
        let showOriginal = model.comparing || pressed == item.id
        return Color.black.aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image = showOriginal ? item.original : item.corrected {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .topTrailing) { badge(item).padding(6) }
            .overlay { if item.state == .loading { ProgressView() } }
            .contentShape(Rectangle())
            .onTapGesture { if item.analysis != nil { detail = item.id } }
            .onLongPressGesture(minimumDuration: 0.25, perform: {}, onPressingChanged: { pressed = $0 ? item.id : nil })
            .accessibilityElement().accessibilityLabel(label(item, showOriginal: showOriginal))
            .accessibilityValue(item.override == nil ? "" : String(localized: "Edited"))
            .accessibilityAddTraits(.isButton)
    }

    private func label(_ item: BatchModel.Item, showOriginal: Bool) -> String {
        switch item.state {
        case .failed: String(localized: "Couldn’t open this photo")
        case .saveFailed: String(localized: "Couldn’t save this photo")
        default: item.previewFailed ? String(localized: "Preview unavailable")
            : showOriginal ? String(localized: "Original") : String(localized: "Corrected")
        }
    }

    @ViewBuilder private func badge(_ item: BatchModel.Item) -> some View {
        switch item.state {
        case .failed, .saveFailed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        case .saved: Image(systemName: "checkmark.circle.fill").foregroundStyle(.mint)
        default:
            if item.previewFailed { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow) }
            else if item.override != nil { Image(systemName: "slider.horizontal.3").foregroundStyle(.white) }
        }
    }

    private func controls(presetGrid: Bool = false) -> some View {
        @Bindable var model = model
        return VStack(spacing: 12) {
            HStack {
                Text(model.comparing ? String(localized: "Original") : model.shared.preset.localizedName)
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                if ExportOptions.PhotoFormat.available.count > 1 {
                    Picker("Format", selection: $model.format) {
                        ForEach(ExportOptions.PhotoFormat.available) { Text(verbatim: $0.name).tag($0) }
                    }.pickerStyle(.menu).frame(minHeight: 44).accessibilityIdentifier("batch-photo-format")
                }
                Button { model.comparing.toggle() } label: {
                    Label("Compare", systemImage: model.comparing ? "eye.fill" : "eye").lineLimit(1).fixedSize()
                }
                    .buttonStyle(.bordered).frame(minHeight: 44)
                    .accessibilityValue(model.comparing ? "Original" : "Corrected")
            }
            LookControls(look: $model.shared, grid: presetGrid)
            if model.shared.preset == .custom {
                // The bar sits over the grid, so the five sliders scroll instead of covering it.
                ScrollView { CustomAdjustmentControls(adjustments: $model.adjustments) }.frame(maxHeight: 200)
            }
            Button { model.saveAll(purchases: purchases) } label: {
                Text("Save All (\(model.pendingCount))").frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.borderedProminent).disabled(model.pendingCount == 0)
        }.padding(.horizontal).padding(.vertical, 8)
    }

    private var savingProgress: some View {
        VStack(spacing: 20) {
            ProgressView(value: Double(model.savedCount), total: Double(max(1, model.saveTotal))).frame(width: 220)
            Text("Saving \(min(model.savedCount + 1, model.saveTotal)) of \(model.saveTotal)…")
            Text("Keep UnderBlue open until saving finishes.").font(.footnote)
            Button("Cancel") { model.saveTask?.cancel() }.frame(minHeight: 44)
        }.padding(30).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct DetailID: Identifiable { let id: BatchModel.Item.ID }
private struct ThumbnailKey: Equatable { let look: BatchModel.Look; let adjustments: CustomAdjustments }

/// Preset chips and intensity slider shared by the batch grid and the single-photo detail.
/// Custom has no intensity, so its slider is hidden.
struct LookControls: View {
    @Binding var look: BatchModel.Look
    /// A two-column grid instead of one row that scrolls sideways. Used in a narrow, tall pane.
    var grid = false
    var body: some View {
        VStack(spacing: 12) {
            if grid {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(DivePreset.allCases) { presetButton($0) }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) { ForEach(DivePreset.allCases) { presetButton($0) } }
                }
            }
            if look.preset != .custom {
                HStack {
                    Text("Intensity")
                    Slider(value: $look.intensity, in: 0...1).accessibilityLabel("Filter intensity")
                        .disabled(look.preset == .original)
                    Text(look.intensity, format: .percent.precision(.fractionLength(0))).monospacedDigit().frame(width: 48, alignment: .trailing)
                }
            }
        }
    }

    private func presetButton(_ preset: DivePreset) -> some View {
        Button { look.preset = preset } label: {
            VStack(spacing: 6) {
                Image(systemName: preset.symbolName).font(.title3)
                Text(preset.localizedName).font(.caption.weight(.medium))
            }.frame(minWidth: grid ? 0 : 84, maxWidth: grid ? .infinity : nil, minHeight: 60).padding(.horizontal, 4)
                .background(look.preset == preset ? Color.mint.opacity(0.2) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(look.preset == preset ? Color.mint : .clear))
        }.buttonStyle(.plain).accessibilityAddTraits(look.preset == preset ? .isSelected : [])
    }
}

/// Full-screen pager. Swipe between photos; a change here overrides the shared look for that photo only.
struct BatchDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let model: BatchModel
    @State var selection: BatchModel.Item.ID
    @State private var preview: CGImage?
    @State private var originalPreview: CGImage?
    @State private var previewFailed = false
    @State private var comparing = false

    private var item: BatchModel.Item? { model.items.first { $0.id == selection } }
    private var ready: [BatchModel.Item] { model.items.filter { $0.analysis != nil } }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                if let fold = EditorView.foldSplit(in: geometry) {
                    FoldPanes(fold: fold, height: geometry.size.height, first: pager) { paneHeight in
                        ScrollView { detailControls(grid: fold.axis == .horizontal).frame(maxWidth: .infinity, minHeight: paneHeight, alignment: .center) }
                    }
                } else {
                    VStack(spacing: 12) {
                        pager
                        detailControls(grid: false)
                    }
                }
            }
            .navigationTitle(position).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task(id: RenderKey(id: selection, look: item.map(model.look(for:)))) { await render() }
            .task(id: selection) { await renderOriginal() }
        }
    }

    private var pager: some View {
        TabView(selection: $selection) {
            ForEach(ready) { page in
                ZStack {
                    Color.black
                    // A failed render must not fall back to the thumbnail: it may show an older look.
                    if page.id == selection, previewFailed, !comparing {
                        Label("Preview unavailable", systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                    } else if page.id == selection, let image = comparing ? (originalPreview ?? page.original) : (preview ?? page.corrected) {
                        Image(decorative: image, scale: 1).resizable().scaledToFit().accessibilityLabel("Photo preview")
                    }
                }.tag(page.id)
            }
        }.tabViewStyle(.page(indexDisplayMode: .never))
    }

    @ViewBuilder private func detailControls(grid: Bool) -> some View {
        if let item {
            VStack(spacing: 12) {
                HStack {
                    if item.override != nil {
                        Button("Reset to batch settings") { model.setOverride(nil, for: item.id) }
                    }
                    Spacer()
                    Button { comparing.toggle() } label: {
                        Label("Compare", systemImage: comparing ? "eye.fill" : "eye").lineLimit(1).fixedSize()
                    }
                        .buttonStyle(.bordered).frame(minHeight: 44)
                        .accessibilityValue(comparing ? "Original" : "Corrected")
                }
                LookControls(look: Binding(get: { model.look(for: item) },
                                           set: { model.setOverride($0, for: item.id) }), grid: grid)
            }.padding(.horizontal).padding(.bottom, 8)
        }
    }

    private var position: String {
        guard let index = ready.firstIndex(where: { $0.id == selection }) else { return "" }
        return String(localized: "\(index + 1) of \(ready.count)")
    }

    private struct RenderKey: Equatable { let id: BatchModel.Item.ID; let look: BatchModel.Look? }

    private func renderOriginal() async {
        originalPreview = nil
        guard let item else { return }
        do { originalPreview = try await model.photos.preview(item.url, settings: .init(), original: true) }
        catch is CancellationError {} catch { await model.recordPreviewFailure(error) }
    }

    private func render() async {
        preview = nil
        previewFailed = false
        guard let item else { return }
        let settings = model.settings(for: item)
        do {
            let image = try await model.photos.preview(item.url, settings: settings, original: false)
            try Task.checkCancellation()
            preview = image
            await model.refreshThumbnails(only: item.id)
        } catch is CancellationError {} catch {
            previewFailed = true
            await model.recordPreviewFailure(error)
        }
    }
}
