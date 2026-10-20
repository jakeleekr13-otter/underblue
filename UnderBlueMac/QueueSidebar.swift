import SwiftUI

struct QueueSidebar: View {
    @Environment(MacModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            ForEach(model.engine.items) { item in
                QueueRow(item: item)
                    .tag(item.id)
                    .contextMenu {
                        if item.state == .done, model.canShowResults {
                            Button(model.showResultsTitle) { model.reveal(item.id) }
                            Divider()
                        }
                        Button("Remove") { model.remove(item.id) }.disabled(model.engine.running)
                    }
            }
        }
        .onDeleteCommand { if let id = model.selection { model.remove(id) } }
        .overlay {
            if model.engine.items.isEmpty {
                ContentUnavailableView {
                    Label("Drop photos and videos here", systemImage: "square.and.arrow.down")
                } description: {
                    Text("Or press ⌘O. Folders work too.")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !model.engine.items.isEmpty {
                let total = model.engine.items.count, done = model.engine.doneCount
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: Double(done), total: Double(max(1, total)))
                    Text(summary(done: done, total: total, failed: model.engine.failedCount)).font(.caption).foregroundStyle(.secondary)
                    if done > 0, model.canShowResults {
                        Button(model.showResultsTitle) { model.showResults() }.buttonStyle(.link).font(.caption)
                    }
                }.padding(10).background(.bar)
            }
        }
    }

    private func summary(done: Int, total: Int, failed: Int) -> String {
        failed == 0 ? String(localized: "\(done) of \(total) saved") : String(localized: "\(done) of \(total) saved, \(failed) failed")
    }
}

struct QueueRow: View {
    let item: BatchEngine.Item

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.kind == .video ? "video" : "photo").foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.originalName ?? item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                if item.state == .exporting, item.kind == .video {
                    ProgressView(value: item.progress)
                } else {
                    Text(status).font(.caption).foregroundStyle(item.state == .failed ? .red : .secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if item.state == .done { Image(systemName: "checkmark.circle.fill").foregroundStyle(.mint) }
            if item.state == .failed { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red) }
        }
    }

    private var status: String {
        switch item.state {
        case .queued: String(localized: "Waiting")
        case .analyzing: String(localized: "Analyzing…")
        case .waiting: String(localized: "Ready to save")
        case .waitingForMemory: String(localized: "Waiting for memory")
        case .exporting: String(localized: "Exporting…")
        case .delivering: String(localized: "Saving…")
        case .done: item.savedName ?? String(localized: "Saved")
        case .failed: item.error ?? String(localized: "Failed")
        case .cancelled: String(localized: "Cancelled")
        }
    }
}
