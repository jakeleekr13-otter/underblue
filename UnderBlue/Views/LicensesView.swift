import SwiftUI

/// The bundled depth model is Apple's Core ML version of Depth Anything V2 Small, under the
/// Apache License 2.0 (model card: huggingface.co/apple/coreml-depth-anything-v2-small). The license
/// asks that it ships with a copy of the license, so Help shows it in full.
struct LicensesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("UnderBlue includes the following open-source software. Its license follows.")
                Text(verbatim: "Depth Anything V2 Small (Core ML)")
                    .font(.headline)
                Text(verbatim: "Depth Anything V2 by Lihe Yang et al. Core ML conversion by Apple (huggingface.co/apple/coreml-depth-anything-v2-small). Licensed under the Apache License, Version 2.0.")
                    .font(.footnote)
                Text(verbatim: Self.licenseText)
                    .font(.caption)
                    .textSelection(.enabled)
            }.padding()
        }
        #if os(iOS)
        // On macOS a navigation title would replace the title of the window that shows this view.
        .navigationTitle("Open-source licenses").navigationBarTitleDisplayMode(.inline)
        #endif
    }
    private static let licenseText: String = {
        guard let url = Bundle.main.url(forResource: "Apache-2.0", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "Apache License, Version 2.0: https://www.apache.org/licenses/LICENSE-2.0" }
        // The file wraps at 80 columns. On a phone that wraps again into ragged lines, so each
        // paragraph becomes one line. The words stay the same.
        return text.components(separatedBy: "\n\n")
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }()
}
