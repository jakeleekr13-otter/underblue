import SwiftUI

/// The Help window: a short guide, support links, local diagnostics and the open-source license.
/// It follows the iPhone Help sheet (DiagnosticsView) with the Mac wording.
struct HelpView: View {
    @Environment(DiagnosticsCenter.self) private var diagnostics
    @Environment(PurchaseStore.self) private var purchases
    @State private var report: URL?
    @State private var error: String?
    @State private var working = false
    @State private var showLicenses = false

    var body: some View {
        #if DEBUG
        // For screenshots: shows only the license page, so no scrolling is needed.
        if CommandLine.arguments.contains("--ui-demo-licenses-only") { LicensesView().frame(minWidth: 520, minHeight: 560) } else { form }
        #else
        form
        #endif
    }

    private var form: some View {
        Form {
            Section {
                step(1, "Add photos, videos or whole folders: drag them into the window or press ⌘O. You can also use Share in Finder or Photos.")
                step(2, "Pick a look on the right: Natural Dive, Tropical or Deep Dive. Strength sets how strong it is.")
                step(3, "Custom starts from the Natural Dive result. Adjust it with five sliders.")
                step(4, "Choose Original or Corrected above the preview to compare. ⌘\\ switches between them.")
                step(5, "Press Start (⌘R). UnderBlue corrects every item in the list and saves each result. Stop (⌘.) keeps the finished ones.")
                step(6, "Choose where results go, a folder or the Photos library, in Settings (⌘,).")
            } header: { Text("Guide") } footer: {
                Text("Results depend on the original. Very dark or very bright scenes may not look as you expect. The same goes for photos and videos that were already edited.")
            }
            Section {
                Label("With Pro, correct as many photos and videos as you like in one batch.", systemImage: "square.grid.2x2")
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
                Text("Diagnostics stay on this Mac. Nothing is sent automatically.")
                Text("The report includes error codes and Apple performance diagnostics, which may contain approximate times and device, OS and app details. It excludes your photos, videos, filenames and location.")
                    .font(.footnote).foregroundStyle(.secondary)
                HStack {
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
                    if working { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("Delete local diagnostics", role: .destructive) {
                        Task { await diagnostics.recorder.clear(); TemporaryFiles.remove(report); report = nil }
                    }.disabled(working)
                }
            }
            Section {
                DisclosureGroup("Open-source licenses", isExpanded: $showLicenses) {
                    LicensesView().frame(height: 300)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 560)
        .onDisappear { TemporaryFiles.remove(report) }
        .alert("Couldn’t finish", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private static let supportEmail = "support@enheart.me"

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        Label { Text(text) } icon: { Image(systemName: "\(number).circle").foregroundStyle(.mint) }
    }
}

/// The credits line of the About panel. The version and the icon come from the app itself.
enum AboutCredits {
    static var text: NSAttributedString {
        let body = NSMutableAttributedString(
            string: "Restores colour and clarity in underwater photos and videos. Everything is processed on this Mac.\n\n"
                + "Includes Depth Anything V2 Small (Core ML) by Lihe Yang et al., converted by Apple, under the Apache License 2.0. "
                + "The full license is in Help ▸ Open-source licenses.\n\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor])
        for (title, address) in [("Support", "https://jakeleekr13-otter.github.io/underblue-support/support/"),
                                 ("Privacy policy", "https://jakeleekr13-otter.github.io/underblue-support/privacy/")] {
            body.append(NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 11), .link: URL(string: address)!]))
            if title == "Support" { body.append(NSAttributedString(string: "   ")) }
        }
        return body
    }
}
