import SwiftUI

@main
struct UnderBlueMacApp: App {
    @State private var model = MacModel()

    var body: some Scene {
        // One window only: it owns the queue, and a second window would start a second queue.
        Window("UnderBlue", id: "main") {
            MainWindow()
                .environment(model).environment(model.purchases).environment(model.trial).environment(model.diagnostics)
                .preferredColorScheme(.dark).tint(.mint)
                .task { await model.purchases.load() }
                .task { await model.importShared() }
                // The share extension opens underblue://share. Becoming active covers a refused open.
                .onOpenURL { url in if url.scheme == SharedInbox.openURL.scheme { Task { await model.importShared() } } }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    Task { await model.importShared() }
                }
        }
        .defaultSize(width: 1200, height: 760)
        .commands { MacCommands(model: model) }
        Window("UnderBlue Help", id: "help") {
            DiagnosticsView().environment(model.purchases).environment(model.diagnostics)
                .preferredColorScheme(.dark).tint(.mint)
        }
        .defaultSize(width: 560, height: 680)
        Settings {
            SettingsView().environment(model)
        }
    }
}

struct MacCommands: Commands {
    let model: MacModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About UnderBlue") {
                NSApp.orderFrontStandardAboutPanel(options: [.credits: AboutCredits.text])
            }
        }
        CommandGroup(after: .appInfo) {
            // Buy, Restore Purchase and Redeem Code live on this screen, so it must open without a blocked export.
            Button("UnderBlue Pro…") { model.paywallReason = nil; model.showPaywall = true }
        }
        CommandGroup(replacing: .help) {
            Button("UnderBlue Help") { openWindow(id: "help") }
                .keyboardShortcut("?")
        }
        CommandGroup(replacing: .newItem) {
            Button("Add Photos and Videos…") { model.showImporter = true }
                .keyboardShortcut("o")
                .disabled(model.engine.running)
        }
        CommandMenu("Batch") {
            Button("Correct") { model.start() }
                .keyboardShortcut("r")
                .disabled(!model.canStart)
            Button("Stop") { model.cancel() }
                .keyboardShortcut(".")
                .disabled(!model.engine.running)
            Divider()
            Button(model.showResultsTitle) { model.showResults() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(!model.canShowResults)
            Button("Retry Failed") { model.retryFailed() }
                .disabled(model.engine.running || model.engine.failedCount == 0)
            Button("Remove Finished") { model.clearFinished() }
                .disabled(model.engine.running || model.engine.doneCount == 0)
        }
        CommandGroup(after: .toolbar) {
            Button(model.showingOriginal ? "Show Corrected" : "Show Original") { model.showingOriginal.toggle() }
                .keyboardShortcut("\\")
        }
    }
}
