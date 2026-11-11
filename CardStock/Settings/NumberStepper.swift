import SwiftUI

/// A number you type, with − and + buttons (hold to repeat) and a Reset
/// button that goes back to `resetValue`. For settings where an exact
/// number matters more than dragging a slider.
struct NumberStepper: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var unit = "px"
    /// True while the setting is at its reset value (Reset is dimmed).
    var isReset: Bool
    var resetHelp = "Reset"
    let reset: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            TextField("", value: Binding(
                get: { value },
                set: { value = clamp($0.rounded()) }), format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 52)
                .labelsHidden()
            Text(unit).foregroundStyle(.secondary)

            Button { value = clamp(value - step) } label: {
                Image(systemName: "minus").frame(width: 14, height: 14)
            }
            .buttonRepeatBehavior(.enabled)
            .disabled(value <= range.lowerBound)
            .help("Smaller")
            .accessibilityLabel("Smaller")

            Button { value = clamp(value + step) } label: {
                Image(systemName: "plus").frame(width: 14, height: 14)
            }
            .buttonRepeatBehavior(.enabled)
            .disabled(value >= range.upperBound)
            .help("Larger")
            .accessibilityLabel("Larger")

            Button(action: reset) {
                Image(systemName: "arrow.counterclockwise").frame(width: 14, height: 14)
            }
            .disabled(isReset)
            .help(resetHelp)
            .accessibilityLabel(resetHelp)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func clamp(_ v: Double) -> Double { min(max(v, range.lowerBound), range.upperBound) }
}
