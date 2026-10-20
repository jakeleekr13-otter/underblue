import SwiftUI

/// The look controls. They apply to every item in the queue.
struct InspectorView: View {
    @Environment(MacModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Look for all items") {
                Picker("Look", selection: $model.preset) {
                    ForEach(DivePreset.allCases) { Text($0.localizedName).tag($0) }
                }
                .pickerStyle(.radioGroup).labelsHidden()
                if model.preset != .original && model.preset != .custom {
                    LabeledContent("Intensity") {
                        Slider(value: $model.intensity, in: 0...1)
                    }
                }
            }
            if model.preset == .custom {
                Section("Custom") { CustomAdjustmentControls(adjustments: $model.adjustments) }
            }
            Section("Photos") {
                Picker("Format", selection: $model.format) {
                    ForEach(ExportOptions.PhotoFormat.available) { Text($0.name).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
        .disabled(model.engine.running)
    }
}
