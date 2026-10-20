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
         "For a video, Play 3s plays three seconds from the current position, then returns.",
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
