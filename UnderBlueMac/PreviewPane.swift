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
                VStack(spacing: 6) {
                    HStack(spacing: 12) {
                        Picker("View", selection: $model.showingOriginal) {
                            Text("Corrected").tag(false)
                            Text("Original").tag(true)
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 220)
                        if model.canPickSubjects { subjectControls }
                    }
                    if model.canPickSubjects { subjectText }
                }.padding(10)
            }
        }
        .onChange(of: model.selection) { _, _ in zoom = PreviewZoom() }
    }

    @ViewBuilder private var content: some View {
        if let item = model.selectedItem {
            if let error = model.previewError {
                ContentUnavailableView("Preview unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if item.kind == .photo {
                if let image = model.showingOriginal ? model.originalImage : model.correctedImage {
                    // The picker shows over the corrected image only. The Original view hides it.
                    let picking = model.subjects.showsOverlay && !model.showingOriginal
                    ZoomablePreview(image: image, zoom: $zoom, overlayActive: picking) { size in
                        if picking, let candidates = model.subjects.candidates {
                            SubjectPicker(candidates: candidates, picks: model.subjects.picks, size: size, zoom: zoom.scale) { model.toggleSubject($0) }
                        }
                    }
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

    /// Subjects: Auto or Manual, then Done or Edit and Reset while Manual. Beside the Corrected or Original picker.
    private var subjectControls: some View {
        let subjects = model.subjects
        return HStack(spacing: 8) {
            Picker("Subjects", selection: Binding(
                get: { subjects.isManual },
                set: { manual in if manual { model.chooseManualSubjects() } else { model.chooseAutoSubjects() } })) {
                Text("Auto subjects").tag(false)
                Text("Pick subjects").tag(true)
            }.pickerStyle(.segmented).labelsHidden().frame(width: 220).disabled(subjects.isDetecting)
                .accessibilityLabel("Subjects")
            if subjects.isManual {
                if subjects.showsOverlay {
                    Button("Done") { model.finishSubjectPicking() }
                } else {
                    Button { model.editSubjects() } label: { Label("Edit", systemImage: "pencil") }
                }
                Button("Reset") { model.resetSubjects() }
            }
        }
    }

    private var subjectText: some View {
        let subjects = model.subjects
        return VStack(spacing: 2) {
            Text(SubjectPickerText.summary(subjects))
            if let notice = SubjectPickerText.notice(subjects) { Text(notice).foregroundStyle(.orange) }
        }.font(.footnote).padding(.horizontal, 10).padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
    }
}
