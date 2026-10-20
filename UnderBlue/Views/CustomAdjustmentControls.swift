import SwiftUI

/// The five Custom sliders and Reset, shared by the editor and the batch screen.
/// Each slider is a position in -1...1, shown as -100...+100. Zero is the automatic result.
struct CustomAdjustmentControls: View {
    @Binding var adjustments: CustomAdjustments

    enum Control: CaseIterable, Identifiable {
        case brightness, contrast, saturation, clarity, temperature
        var id: Self { self }
        var title: LocalizedStringResource {
            switch self {
            case .brightness: "Brightness"
            case .contrast: "Contrast"
            case .saturation: "Saturation"
            case .clarity: "Clarity"
            case .temperature: "Temperature"
            }
        }
        var keyPath: WritableKeyPath<CustomAdjustments, Float> {
            switch self {
            case .brightness: \.brightness
            case .contrast: \.contrast
            case .saturation: \.saturation
            case .clarity: \.clarity
            case .temperature: \.temperature
            }
        }
    }

    /// "+30", "0" or "-30".
    nonisolated static func valueText(_ position: Float) -> String {
        let value = Int((min(1, max(-1, position.isFinite ? position : 0)) * 100).rounded())
        return value > 0 ? "+\(value)" : "\(value)"
    }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Control.allCases) { control in
                let text = Self.valueText(adjustments[keyPath: control.keyPath])
                VStack(spacing: 2) {
                    HStack {
                        Text(control.title)
                        Spacer()
                        Text(text).monospacedDigit().foregroundStyle(.secondary)
                    }.accessibilityHidden(true)
                    slider(for: control)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(Text(control.title))
                        .accessibilityValue(Text(text))
                }
            }
            Button("Reset") { adjustments = .zero }
                .buttonStyle(.bordered).frame(minHeight: 44)
                .disabled(atZero)
        }
    }
    @ViewBuilder private func slider(for control: Control) -> some View {
        let value = $adjustments[dynamicMember: control.keyPath]
        #if os(macOS)
        // A stepped slider draws one tick mark per step on macOS, and 200 marks look like noise under the track.
        // So the slider is smooth and the value is rounded to the same 0.01 step.
        Slider(value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = ($0 * 100).rounded() / 100 }), in: -1...1)
        #else
        Slider(value: value, in: -1...1, step: 0.01)
        #endif
    }

    /// Slider steps can leave a tiny remainder near zero, so "all at zero" means every shown value is 0.
    private var atZero: Bool { Control.allCases.allSatisfy { Self.valueText(adjustments[keyPath: $0.keyPath]) == "0" } }
}
