import AVKit
import SwiftUI

struct PreviewPane: View {
    @Environment(MacModel.self) private var model
    @State private var zoom = PreviewZoom()

    /// The Labs switch lives in Help, a separate window on the Mac. This keeps the model in step with it.
    @AppStorage(SubjectPickerStore.key) private var subjectPickerSwitch = false
    /// The Labs orb switch (PhotoOrbs.enabledKey). The processor reads it at render time; this redraws the preview.
    @AppStorage(PhotoOrbs.enabledKey) private var removeOrbsSwitch = false

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
                    if model.canPickSubjects, model.subjectPickerEnabled { subjectText }
                }.padding(10)
            }
        }
        .onChange(of: model.selection) { _, _ in zoom = PreviewZoom() }
        .onChange(of: subjectPickerSwitch, initial: true) { _, on in model.subjectPickerEnabled = on && SubjectPickerStore.isSupported }
        .onChange(of: removeOrbsSwitch) { _, _ in model.orbSwitchChanged() }
        .onChange(of: PreciseModelLoader.shared.isReady) { _, ready in if ready { model.preciseModelReady() } }
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
                        if picking, model.subjects.isManual {
                            let pressed = model.subjects.pressed ?? .empty
                            SubjectPicker(candidates: pressed, picks: Set(pressed.groups.map(\.id)), size: size, zoom: zoom.scale,
                                          pressMode: true, pressing: model.subjects.pressing,
                                          onPress: { model.pressSubject(at: $0) }) { model.removeSubjectPress($0) }
                        } else if picking, let candidates = model.subjects.candidates {
                            SubjectPicker(candidates: candidates, picks: model.subjects.picks, tiers: model.subjects.tiers, tierPieces: model.subjects.tierPieces,
                                          tierDrawing: model.subjects.tierDrawing, tiersOff: model.subjects.tiersOff,
                                          size: size, zoom: zoom.scale, onToggleTier: { model.toggleTier($0) }) { model.toggleSubject($0) }
                        }
                    }
                    .overlay(alignment: .bottomTrailing) { PreviewRenderingIndicator(active: model.previewRendering) }
                } else {
                    ProgressView()
                }
            } else if let player = model.player {
                VideoPlayer(player: player)
                    // The original plays until the scene analysis is done (MacModel.buildVideoPreview).
                    .overlay(alignment: .topTrailing) {
                        if model.analysingSelectedVideo {
                            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Analyzing…").font(.footnote.weight(.medium)) }
                                .padding(8).background(.regularMaterial, in: Capsule()).padding(12)
                        }
                    }
            } else {
                ProgressView()
            }
        } else {
            ContentUnavailableView("No item selected", systemImage: "photo.on.rectangle", description: Text("Add photos or videos, then pick one in the list."))
        }
    }

    /// Subjects: Auto, Semi-auto or Manual, then Done or Edit and Reset, and the strength once something is picked.
    /// Beside the Corrected or Original picker.
    private var subjectControls: some View {
        let subjects = model.subjects
        return HStack(spacing: 8) {
            if model.subjectPickerEnabled { subjectBar(subjects) }
        }
    }

    @ViewBuilder private func subjectBar(_ subjects: SubjectSelection) -> some View {
        HStack(spacing: 8) {
            Picker("Subjects", selection: Binding(
                get: { subjects.mode },
                set: { mode in
                    switch mode {
                    case .auto: model.chooseAutoSubjects()
                    case .semiAuto: model.chooseSemiAutoSubjects()
                    case .manual: model.chooseManualSubjects()
                    }
                })) {
                Text("Auto").tag(SubjectSelection.Mode.auto)
                Text("Semi-auto").tag(SubjectSelection.Mode.semiAuto)
                Text("Manual").tag(SubjectSelection.Mode.manual)
            }.pickerStyle(.segmented).labelsHidden().frame(width: 280).disabled(subjects.isDetecting || subjects.pressing != nil)
                .accessibilityLabel("Subjects")
            if subjects.mode != .auto {
                if subjects.showsOverlay {
                    Button("Done") { model.finishSubjectPicking() }
                } else {
                    Button { model.editSubjects() } label: { Label("Edit", systemImage: "pencil") }
                }
                Button("Reset") { model.resetSubjects() }
            }
            if subjects.showsStrength {
                SubjectStrengthSlider(strength: subjects.strength, compact: true) { model.setSubjectStrength($0) }
            }
        }
    }

    private var subjectText: some View {
        let subjects = model.subjects
        return VStack(spacing: 2) {
            Text(SubjectPickerText.summary(subjects))
            if let legend = SubjectPickerText.legend(subjects) { Text(legend).foregroundStyle(.secondary) }
            if let notice = SubjectPickerText.notice(subjects) { Text(notice).foregroundStyle(.orange) }
        }.font(.footnote).padding(.horizontal, 10).padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
    }
}
