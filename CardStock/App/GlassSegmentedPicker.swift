import SwiftUI

/// A segmented control made of Liquid Glass: a glass track with a tinted
/// glass pill that slides to the selected option. When the selection
/// matches no option, no pill is shown.
struct GlassSegmentedPicker<Value: Hashable>: View {
    struct Option {
        var value: Value
        var title: String
        var systemImage: String?
        init(_ value: Value, _ title: String, systemImage: String? = nil) {
            self.value = value
            self.title = title
            self.systemImage = systemImage
        }
    }

    @Binding var selection: Value
    let options: [Option]
    /// Total height, including the track's padding.
    var height: CGFloat = 30
    @Namespace private var namespace

    private let inset: CGFloat = 3

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                segment(options[i])
            }
        }
        .padding(inset)
        .frame(height: height)
        .glassEffect(.regular.interactive(), in: .capsule)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func segment(_ option: Option) -> some View {
        let selected = selection == option.value
        return Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) { selection = option.value }
        } label: {
            HStack(spacing: 5) {
                if let symbol = option.systemImage { Image(systemName: symbol) }
                Text(option.title)
            }
            .font(.callout.weight(selected ? .semibold : .medium))
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .frame(maxHeight: .infinity)
            .background {
                if selected {
                    Capsule()
                        .fill(Color.accentColor.opacity(0.85))
                        .glassEffect(.regular.tint(.accentColor).interactive(), in: .capsule)
                        .matchedGeometryEffect(id: "selection", in: namespace)
                        .shadow(color: Color.accentColor.opacity(0.35), radius: 4, y: 1)
                }
            }
            .contentShape(Capsule())
            .scaleEffect(selected ? 1 : 0.97)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
