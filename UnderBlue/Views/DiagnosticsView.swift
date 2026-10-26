import SwiftUI

/// The Help view, shared by the iPhone app (a sheet) and the Mac app (its own window): a short guide, support links,
/// the diagnostics tools and the open-source license. Only the guide and a few words differ by platform.
struct DiagnosticsView: View {
    @Environment(DiagnosticsCenter.self) private var diagnostics
    @Environment(PurchaseStore.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    @State private var report: URL?
    @State private var error: String?
    @State private var working = false
    @State private var showLicenses = false
    /// Saved on the device, off by default (SubjectPickerStore).
    @AppStorage(SubjectPickerStore.key) private var subjectPicker = false
    /// Saved on the device, off by default (PhotoOrbs.enabledKey).
    @AppStorage(PhotoOrbs.enabledKey) private var removeOrbs = false

    /// The precise model's download, under the Labs switch. Nothing once it is ready.
    @ViewBuilder private var modelStatus: some View {
        switch PreciseModelLoader.shared.state {
        case .downloading(let fraction):
            VStack(alignment: .leading, spacing: 6) {
                Text("Downloading the subject model… \(Int((fraction * 100).rounded()))%").font(.footnote)
                ProgressView(value: fraction)
            }
        case .failed:
            VStack(alignment: .leading, spacing: 6) {
                Text("Couldn’t download the subject model. Check your connection and try again.").font(.footnote)
                Button("Try again") { PreciseModelLoader.shared.start() }
            }
        case .waitingForNetwork:
            Text("Connect to the internet to download the subject model. It downloads by itself when you’re online.").font(.footnote)
        case .idle, .ready:
            EmptyView()
        }
    }

    var body: some View {
        #if os(iOS)
        NavigationStack {
            form.navigationTitle("Help").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        #elseif DEBUG
        // For screenshots: shows only the license page, so no scrolling is needed.
        if CommandLine.arguments.contains("--ui-demo-licenses-only") { LicensesView().frame(minWidth: 520, minHeight: 560) } else { form.frame(minWidth: 520, minHeight: 560) }
        #else
        form.frame(minWidth: 520, minHeight: 560)
        #endif
    }

    private var form: some View {
        Form {
            Section {
                ForEach(Array(Self.guide.enumerated()), id: \.offset) { index, text in step(index + 1, text) }
            } header: { Text("Guide") } footer: {
                Text("Results depend on the original. Very dark or very bright scenes may not look as you expect. The same goes for photos and videos that were already edited.")
            }
            Section {
                #if os(iOS)
                Label(String(localized: "With Pro, select up to \(BatchModel.maxPhotos) photos to correct them together. Tap a photo to give it its own look."),
                      systemImage: "square.grid.2x2")
                #else
                Label("With Pro, correct as many photos and videos as you like in one batch.", systemImage: "square.grid.2x2")
                #endif
                if !purchases.isPro {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Free: 1 photo export and 1 video export (first 10 seconds, up to 1080p SDR).")
                            Text("Failed or cancelled exports don’t use your trial.").font(.footnote).foregroundStyle(.secondary)
                        }
                    } icon: { Image(systemName: "gift") }
                }
            }
            Section {
                // Below 27 the switch stays off and locked (SubjectPickerStore.isSupported).
                Toggle(isOn: Binding(get: { subjectPicker && SubjectPickerStore.isSupported }, set: { subjectPicker = $0 })) {
                    Label("Pick subjects manually", systemImage: "flask")
                }.disabled(!SubjectPickerStore.isSupported)
                    .onChange(of: subjectPicker) { _, on in if on, SubjectPickerStore.isSupported { PreciseModelLoader.shared.start() } }
                if subjectPicker, SubjectPickerStore.isSupported { modelStatus }
            } header: { Label("Labs", systemImage: "flask") } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Experimental. Choose Auto or Manual for the subjects the correction protects.")
                    #if os(iOS)
                    Text("Only when you edit a single photo. Not in batch editing, and not for videos.")
                    #else
                    Text("Only for the photo selected in the preview, one at a time. Not for videos.")
                    #endif
                    if !SubjectPickerStore.isSupported {
                        #if os(iOS)
                        Text("Needs iOS 27 or later.")
                        #else
                        Text("Needs macOS 27 or later.")
                        #endif
                    }
                }
            }
            Section {
                Toggle(isOn: $removeOrbs) { Label("Remove backscatter spots", systemImage: "circle.dotted") }
            } footer: {
                Text("Experimental. Removes faint round spots from floating particles in the water. Photos only. Small fish may fade a little.")
            }
            Section {
                Link(destination: URL(string: "mailto:\(Self.supportEmail)?subject=UnderBlue%20Support")!) {
                    Label { Text(verbatim: Self.supportEmail) } icon: { Image(systemName: "envelope") }
                }
                Link(destination: URL(string: "https://jakeleekr13-otter.github.io/underblue-support/support/")!) {
                    Label("Support website", systemImage: "safari")
                }
                Link(destination: URL(string: "https://jakeleekr13-otter.github.io/underblue-support/privacy/")!) {
                    Label("Privacy policy", systemImage: "hand.raised")
                }
            } header: { Text("Support") } footer: {
                Text("Send photos, videos and diagnostic reports by email. Don’t attach them to a public GitHub issue.")
            }
            Section("Diagnostics") {
                #if os(iOS)
                Text("Diagnostics stay on this iPhone. Nothing is sent automatically.")
                #else
                Text("Diagnostics stay on this Mac. Nothing is sent automatically.")
                #endif
                Text("The report includes error codes and Apple performance diagnostics, which may contain approximate times and device, OS and app details. It excludes your photos, videos, filenames and location.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                if let report {
                    ShareLink("Share diagnostic report", item: report)
                } else {
                    Button("Prepare diagnostic report") {
                        working = true
                        Task {
                            defer { working = false }
                            do { report = try await diagnostics.recorder.exportReport() }
                            catch { self.error = String(localized: "Couldn’t prepare diagnostics. Please try again.") }
                        }
                    }.disabled(working)
                }
                if working { ProgressView() }
                Button("Delete local diagnostics", role: .destructive) {
                    Task { await diagnostics.recorder.clear(); TemporaryFiles.remove(report); report = nil }
                }.disabled(working)
            }
            Section { Text("For a crash, TestFlight and Xcode Organizer may provide a separate Apple crash report. Keep the app build and its debug symbols together.").font(.footnote).foregroundStyle(.secondary) }
            Section {
                #if os(iOS)
                NavigationLink("Open-source licenses") { LicensesView() }
                #else
                DisclosureGroup("Open-source licenses", isExpanded: $showLicenses) { LicensesView().frame(height: 300) }
                #endif
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .onDisappear { TemporaryFiles.remove(report) }
        .alert("Couldn’t finish", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }

    private static let supportEmail = "support@enheart.me"

    /// The guide steps. The wording follows the controls of each app.
    private static var guide: [LocalizedStringKey] {
        #if os(iOS)
        ["Choose a photo or video, or import from Files. You can also share to UnderBlue from the Photos app.",
         "Pick a look: Natural Dive, Tropical or Deep Dive. Intensity sets how strong it is.",
         "Custom starts from the Natural Dive result. Adjust it with five sliders.",
         "Tap Compare to see the original. In the photo editor, pinch or double-tap to zoom.",
         "For a video, 3s Preview plays three seconds from the current position, then returns.",
         "Tap Export, then Save to Photos."]
        #else
        ["Add photos, videos or whole folders: drag them into the window or press ⌘O. You can also use Share in Finder or Photos.",
         "Pick a look: Natural Dive, Tropical or Deep Dive. Intensity sets how strong it is.",
         "Custom starts from the Natural Dive result. Adjust it with five sliders.",
         "Choose Original or Corrected above the preview to compare. ⌘\\ switches between them.",
         "Press Correct (⌘R). UnderBlue corrects every item in the list and saves each result. Stop (⌘.) keeps the finished ones.",
         "Choose where results go, a folder or the Photos library, in Settings (⌘,)."]
        #endif
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        Label { Text(text) } icon: { Image(systemName: "\(number).circle").foregroundStyle(.mint) }
    }
}
