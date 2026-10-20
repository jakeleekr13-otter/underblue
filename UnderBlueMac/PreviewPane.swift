import AVKit
import SwiftUI

struct PreviewPane: View {
    @Environment(MacModel.self) private var model
    @State private var zoom = PreviewZoom()

    var body: some View {
        @Bindable var model = model
        ZStack {
            Color.black.opacity(0.35)
            content
        }
        .overlay(alignment: .top) {
            if model.selectedItem != nil {
                Picker("View", selection: $model.showingOriginal) {
                    Text("Corrected").tag(false)
                    Text("Original").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 220).padding(10)
            }
        }
        .onChange(of: model.selection) { _, _ in zoom = PreviewZoom() }
    }

    @ViewBuilder private var content: some View {
        if let item = model.selectedItem {
            if let error = model.previewError {
                ContentUnavailableView("Can’t show this preview", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if item.kind == .photo {
                if let image = model.showingOriginal ? model.originalImage : model.correctedImage {
                    ZoomablePreview(image: image, zoom: $zoom)
                } else {
                    ProgressView()
                }
            } else if let player = model.player {
                VideoPlayer(player: player)
            } else {
                ProgressView()
            }
        } else {
            ContentUnavailableView("No item selected", systemImage: "photo.on.rectangle", description: Text("Add photos or videos, then pick one in the list."))
        }
    }
}
