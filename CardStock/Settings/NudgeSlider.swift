import SwiftUI

/// A slider with − and + buttons that move it one step at a time (hold to
/// repeat), and its current value shown at the end.
struct NudgeSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var unit = "px"
    /// Converts the stored value for display (e.g. rem → px).
    var display: (Double) -> Double = { $0 }

    var body: some View {
        HStack(spacing: 6) {
            Button { nudge(-step) } label: {
                Image(systemName: "minus")
                    .frame(width: 14, height: 14)
            }
            .buttonRepeatBehavior(.enabled)
            .disabled(value <= range.lowerBound)
            .help("Smaller")

            // No `step:` here, since that draws tick marks; snap by hand instead.
            Slider(value: Binding(
                get: { value },
                set: { value = min(max(($0 / step).rounded() * step, range.lowerBound), range.upperBound) }),
                   in: range)

            Button { nudge(step) } label: {
                Image(systemName: "plus")
                    .frame(width: 14, height: 14)
            }
            .buttonRepeatBehavior(.enabled)
            .disabled(value >= range.upperBound)
            .help("Larger")

            Text("\(Int(display(value).rounded())) \(unit)")
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func nudge(_ delta: Double) {
        value = min(max(value + delta, range.lowerBound), range.upperBound)
    }
}
