import SwiftUI
import UniformTypeIdentifiers

struct MainWindow: View {
    @Environment(MacModel.self) private var model
    @State private var dropTargeted = false
    @State private var showInspector = true

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            QueueSidebar()
                .navigationSplitViewColumnWidth(min: 230, ideal: 290, max: 420)
        } detail: {
            PreviewPane()
        }
        .inspector(isPresented: $showInspector) {
            InspectorView().inspectorColumnWidth(min: 260, ideal: 300, max: 380)
        }
        .toolbar {
            ToolbarItem {
                Button { model.showImporter = true } label: { Label("Add", systemImage: "plus") }
                    .help("Add photos, videos or folders (⌘O)")
                    .disabled(model.engine.running)
            }
            ToolbarItem {
                if model.engine.running {
                    Button { model.cancel() } label: { Label("Stop", systemImage: "stop.fill") }
                        .help("Stop the batch. Finished items are kept (⌘.)")
                } else {
                    Button { model.start() } label: { Label("Correct", systemImage: "wand.and.stars") }
                        .help("Correct everything in the queue (⌘R)")
                        .disabled(!model.canStart)
                }
            }
            ToolbarItem {
                Button { _ = model.chooseFolder() } label: { Label(outputLabel, systemImage: model.saveTarget == .photos ? "photo.on.rectangle" : "folder") }
                    .help(model.saveTarget == .photos ? "Results go to your Photos library. Change this in Settings (⌘,)." : "Choose the output folder")
                    .disabled(model.engine.running || model.saveTarget == .photos)
            }
            ToolbarItem {
                Button { showInspector.toggle() } label: { Label("Look", systemImage: "slider.horizontal.3") }
                    .help("Show or hide the look controls")
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            Task { await model.add(urls) }
            return true
        } isTargeted: { dropTargeted = $0 }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12).strokeBorder(.mint, style: StrokeStyle(lineWidth: 3, dash: [10]))
                    .background(.mint.opacity(0.08)).padding(8).allowsHitTesting(false)
            }
        }
        .fileImporter(isPresented: $model.showImporter, allowedContentTypes: [.image, .movie, .folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { Task { await model.add(urls) } }
        }
        .sheet(isPresented: $model.showPaywall) { ProView(reason: model.paywallReason) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let notice = model.notice {
                HStack {
                    Text(notice).font(.callout)
                    Spacer()
                    Button("OK") { model.notice = nil }.buttonStyle(.link)
                }.padding(.horizontal, 14).padding(.vertical, 8).background(.bar)
            }
        }
        .frame(minWidth: 900, minHeight: 560)
    }

    private var outputLabel: String {
        switch model.saveTarget {
        case .photos: String(localized: "Photos library")
        case .folder: model.folderURL?.lastPathComponent ?? String(localized: "Choose Folder")
        }
    }
}
