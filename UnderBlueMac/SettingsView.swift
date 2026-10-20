import SwiftUI

struct SettingsView: View {
    @Environment(MacModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Save results to") {
                Picker("Place", selection: $model.saveTarget) {
                    Text("A folder").tag(MacModel.SaveTarget.folder)
                    Text("Photos library").tag(MacModel.SaveTarget.photos)
                }
                .pickerStyle(.radioGroup)
                if model.saveTarget == .folder {
                    LabeledContent("Folder") {
                        HStack {
                            Text(model.folderURL?.path(percentEncoded: false) ?? String(localized: "Not chosen yet"))
                                .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                            Button("Choose…") { _ = model.chooseFolder() }
                        }
                    }
                }
            }
            Section("Photos") {
                Picker("Format", selection: $model.format) {
                    ForEach(ExportOptions.PhotoFormat.available) { Text($0.name).tag($0) }
                }
                Toggle("Keep HDR when possible", isOn: $model.preferHDR)
            }
            Section("Speed") {
                Stepper("Most photos at the same time: \(model.parallelPhotos)", value: $model.parallelPhotos, in: 1...4)
                Text("This is a limit. UnderBlue starts fewer when the Mac is low on memory, and waits when a large photo needs most of it. It applies to the next batch.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}
