import SwiftUI

struct ExportView: View {
    @Environment(PurchaseStore.self) private var purchases
    @Environment(TrialStore.self) private var trial
    @Bindable var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                // First, so the 10-second limit is seen before the options.
                if !purchases.isPro {
                    Section("Free trial") {
                        Text(model.media.kind == .photo ? String(localized: "Free export with an UnderBlue watermark.") : String(localized: "Free export: first 10 seconds · up to 1080p SDR · UnderBlue watermark."))
                            .accessibilityIdentifier(model.media.kind == .photo ? "photo-trial-description" : "video-trial-description")
                        Text(allowance).font(.footnote)
                        Text("Failed or cancelled exports don’t use your trial.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let metadata = model.metadata {
                    Section("Resolution") {
                        // `.disabled` on a picker row did not stop the tap: a free user could pick Quick (UI test,
                        // 10 Nov 2026). The binding refuses a choice the user may not make; the row shows a lock.
                        Picker("Resolution", selection: Binding(get: { model.options.resolution }, set: {
                            if ExportOptions.allows($0, pro: purchases.isPro) { model.options.resolution = $0 }
                        })) {
                            ForEach(ExportOptions.Resolution.allCases) { resolution in
                                let allowed = ExportOptions.allows(resolution, pro: purchases.isPro)
                                HStack {
                                    if resolution == .source, ExportOptions.exceedsSupportedSize(metadata.displaySize) {
                                        Text(verbatim: "4K")
                                    } else if resolution == .quick {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(resolution.localizedName)
                                            Text(verbatim: Self.quickDetail(metadata, rotation: model.rotation)).font(.caption).foregroundStyle(.secondary)
                                        }
                                    } else {
                                        Text(resolution.localizedName)
                                    }
                                    if resolution == .source, ExportOptions.isBest(metadata.displaySize) {
                                        Text("Best").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(.tint.opacity(0.2), in: Capsule()).foregroundStyle(.tint)
                                    }
                                    Spacer()
                                    if !allowed {
                                        Image(systemName: "lock.fill").font(.footnote).foregroundStyle(.secondary)
                                    } else if let seconds = model.estimates[resolution] {
                                        Text("~" + Self.format(seconds)).monospacedDigit().foregroundStyle(.secondary)
                                    } else if model.estimating { ProgressView() }
                                }.foregroundStyle(allowed ? .primary : .secondary).tag(resolution)
                            }
                        }.pickerStyle(.inline).labelsHidden()
                        Text(model.options.summary(for: metadata)).font(.footnote).foregroundStyle(.secondary)
                        if ExportOptions.exceedsSupportedSize(metadata.displaySize) {
                            Text("8K video isn’t supported yet. It exports in 4K, the best option.").font(.footnote).foregroundStyle(.secondary)
                        }
                        Text("Estimated time comes from earlier exports on this device.").font(.footnote).foregroundStyle(.secondary)
                        Text("Other apps running at the same time can slow the export.").font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("Quality") {
                        // Each resolution starts at its own default level. Free users keep Standard.
                        Picker("Quality", selection: Binding(get: { model.options.quality }, set: {
                            if ExportOptions.allows($0, pro: purchases.isPro) { model.options.quality = $0 }
                        })) {
                            ForEach(ExportOptions.Quality.allCases) { quality in Text(quality.localizedName).tag(quality) }
                        }.pickerStyle(.segmented).disabled(!purchases.isPro).accessibilityIdentifier("export-quality")
                        Text("Higher quality keeps more detail and makes a larger file.").font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("Color") {
                        Picker("Color", selection: Binding(get: { model.options.range }, set: {
                            if $0 == .sdr || (model.capability.hdrAvailable && purchases.isPro) { model.options.range = $0 }
                        })) {
                            Text("SDR").tag(ExportOptions.Range.sdr)
                            Text("HDR").tag(ExportOptions.Range.hdr).disabled(!model.capability.hdrAvailable || !purchases.isPro)
                        }.pickerStyle(.segmented).accessibilityIdentifier("video-range")
                        Text(model.capability.explanation).font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Text(Self.photoSummary(model.options))
                        if !model.capability.hdrAvailable { Text(model.capability.explanation).font(.footnote).foregroundStyle(.secondary) }
                    }
                    if ExportOptions.PhotoFormat.available.count > 1 {
                        Section("Format") {
                            Picker("Format", selection: $model.options.photoFormat) {
                                ForEach(ExportOptions.PhotoFormat.available) { Text(verbatim: $0.name).tag($0) }
                            }.pickerStyle(.segmented).accessibilityIdentifier("photo-format")
                            Text(model.options.photoFormat == .heic
                                 ? String(localized: "10-bit color keeps water gradients smooth. Files are about twice the size of JPEG, and some older apps can’t open them.")
                                 : String(localized: "Works in almost every app. Saved at the highest JPEG quality."))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if model.capability.hdrAvailable {
                        Section("Color") {
                            Picker("Color", selection: Binding(get: { model.options.range }, set: {
                                if $0 == .sdr || purchases.isPro { model.options.range = $0 }
                            })) {
                                Text("SDR").tag(ExportOptions.Range.sdr)
                                Text("HDR").tag(ExportOptions.Range.hdr).disabled(!purchases.isPro)
                            }.pickerStyle(.segmented)
                            Text(model.capability.explanation).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }.navigationTitle("Export").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                // Pinned so the action stays visible however far the options scroll.
                .safeAreaInset(edge: .bottom) {
                    Button { model.requestStart(purchases: purchases, trial: trial) } label: {
                        Text("Export").frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.borderedProminent).accessibilityIdentifier("export-confirm").padding(.horizontal).padding(.vertical, 8).background(.bar)
                }
        }.presentationDetents([.large])
            .task { if model.media.kind == .video { model.estimateExportTimes(pro: purchases.isPro) } }
            .onChange(of: model.options.range) { if model.media.kind == .video { model.estimateExportTimes(pro: purchases.isPro) } }
            .onChange(of: purchases.isPro) { if model.media.kind == .video { model.estimateExportTimes(pro: purchases.isPro) } }
            .onDisappear { model.cancelEstimates() }
            .alert("Free up memory", isPresented: Binding(get: { model.memoryShortage != nil }, set: { if !$0 { model.memoryShortage = nil } })) {
                Button("Check again") { Task { await model.recheckMemory(purchases: purchases, trial: trial) } }
                Button("Cancel", role: .cancel) { model.memoryShortage = nil }
            } message: {
                Text("There isn’t enough free memory for this video. Close other apps, then choose Check again.")
            }
    }
    nonisolated static func photoSummary(_ options: ExportOptions) -> String {
        switch (options.range, options.photoFormat) {
        case (.sdr, .jpeg): String(localized: "Original resolution · SDR · JPEG")
        case (.hdr, .jpeg): String(localized: "Original resolution · HDR · JPEG with gain map")
        case (.sdr, .heic): String(localized: "Original resolution · SDR · HEIC 10-bit")
        case (.hdr, .heic): String(localized: "Original resolution · HDR · HEIC 10-bit with gain map")
        }
    }
    /// What the trial gives after this export.
    private var allowance: String {
        guard model.media.kind == .photo else { return String(localized: "1 free video every 24 hours.") }
        let left = trial.welcomePhotosLeft
        return left > 0 ? String(localized: "Free photos left: \(left) of \(TrialPolicy.welcomePhotos). Then 1 free photo every 24 hours.")
            : String(localized: "1 free photo every 24 hours.")
    }
    /// What Quick makes from this source: "720p · 30 fps", or the source size when it is already 720p or less.
    /// A tall source fits the 1280 × 720 frame by its long side, so 1182 × 2560 becomes 590 × 1280 (still "720p").
    static func quickDetail(_ metadata: VideoMetadata, rotation: VideoRotation = .none) -> String {
        var quick = ExportOptions()
        quick.resolution = .quick
        let source = rotation.applied(to: metadata.displaySize), size = quick.size(for: source)
        let reduced = max(size.width, size.height) < max(source.width, source.height) - 2
        let label = reduced ? "720p" : "\(Int(size.width)) × \(Int(size.height))"
        return label + " · " + ExportOptions.frameRateText(quick.outputFrameRate(sourceRate: metadata.frameRate))
    }
    static func format(_ seconds: Double) -> String {
        let rounded = seconds < 60 ? max(5, (seconds / 5).rounded(.up) * 5) : (seconds / 60).rounded(.up) * 60
        return Duration.seconds(rounded).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))
    }
}
struct ExportCompleteView: View {
    @Bindable var model: EditorModel
    @Environment(\.openURL) private var openURL
    @State private var confirmDiscard = false
    /// A free video export cuts the clip at the trial limit. Say so when the clip was longer.
    private var trimmed: Bool {
        guard model.media.kind == .video, let limit = model.options.durationLimit, let duration = model.metadata?.duration else { return false }
        return duration > limit + 0.05
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle").font(.system(size: 54)).foregroundStyle(.mint)
                Text("Ready to save").font(.title2.bold())
                Text("Your export has been checked and is ready for Photos.").foregroundStyle(.secondary).multilineTextAlignment(.center)
                if trimmed { Text("Only the first 10 seconds were exported. Pro exports the full video.").font(.subheadline).multilineTextAlignment(.center) }
                if model.options.watermark { Text("This free export carries an UnderBlue watermark. Pro removes it.").font(.subheadline).multilineTextAlignment(.center) }
                Button("Save to Photos") { Task { await model.saveCompleted() } }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.saving)
                if model.saving { ProgressView("Saving…") }
            }.padding(30).navigationTitle("Export complete").navigationBarTitleDisplayMode(.inline)
                // Discard sits in the top corner, away from Save, and asks first. A swipe never closes the sheet,
                // because closing deletes the file (Jake, 4 Nov 2026).
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Discard", role: .destructive) { confirmDiscard = true }.disabled(model.saving)
                    }
                }
                .confirmationDialog("Discard this export?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                    Button("Discard export", role: .destructive) { model.discardCompleted() }
                } message: {
                    if model.options.watermark { Text("Your trial won’t be used.") }
                }
                .alert("Couldn’t save", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                    if model.errorNeedsSettings, let settings = URL(string: UIApplication.openSettingsURLString) {
                        Button("Open Settings") { model.error = nil; openURL(settings) }
                    }
                    Button("OK") { model.error = nil }
                } message: { Text(model.error ?? "") }
        }.interactiveDismissDisabled().presentationDetents([.medium])
    }
}
