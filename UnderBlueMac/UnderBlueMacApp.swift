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
        }
        .defaultSize(width: 1200, height: 760)
        .commands { MacCommands(model: model) }
        Settings {
            SettingsView().environment(model)
        }
    }
}

struct MacCommands: Commands {
    let model: MacModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Photos and Videos…") { model.showImporter = true }
                .keyboardShortcut("o")
                .disabled(model.engine.running)
        }
        CommandMenu("Batch") {
            Button("Start") { model.start() }
                .keyboardShortcut("r")
                .disabled(!model.canStart)
            Button("Stop") { model.cancel() }
                .keyboardShortcut(".")
                .disabled(!model.engine.running)
            Divider()
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
