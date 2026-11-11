import AppKit
import SwiftUI

/// Settings for a 3D model in a page: its description, width, height,
/// background and spin. Opens after picking a model to insert, or from the
/// cube button with the cursor on a model's line, to change it.
struct ModelSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let src: String
    let isNew: Bool
    let save: (_ alt: String, _ options: ModelEmbed.Options) -> Void

    @State private var alt: String
    @State private var options: ModelEmbed.Options
    @State private var color: Color

    private enum BackgroundChoice: Hashable { case theme, transparent, color }

    init(src: String, alt: String, options: ModelEmbed.Options, isNew: Bool,
         save: @escaping (_ alt: String, _ options: ModelEmbed.Options) -> Void) {
        self.src = src
        self.isNew = isNew
        self.save = save
        _alt = State(initialValue: alt)
        _options = State(initialValue: options)
        if case .color(let hex) = options.background, let c = Self.color(hex) {
            _color = State(initialValue: c)
        } else {
            _color = State(initialValue: .white)
        }
    }

    private var backgroundChoice: Binding<BackgroundChoice> {
        Binding(get: {
            switch options.background {
            case .theme: .theme
            case .transparent: .transparent
            case .color: .color
            }
        }, set: { choice in
            switch choice {
            case .theme: options.background = .theme
            case .transparent: options.background = .transparent
            case .color: options.background = .color(Self.hex(color))
            }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Label(isNew ? "Insert a 3D Model" : "3D Model Settings", systemImage: "cube")
                    .font(.title3.bold())
                Text((src as NSString).lastPathComponent)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Form {
                TextField("Description", text: $alt, prompt: Text("What the model is, for people who can't see it"))

                LabeledContent("Width") {
                    NumberStepper(value: Binding(get: { Double(options.width) }, set: { options.width = Int($0) }),
                                  range: Double(ModelEmbed.Options.widths.lowerBound)...Double(ModelEmbed.Options.widths.upperBound),
                                  step: 5, unit: "% of the text width", isReset: options.width == 100,
                                  resetHelp: "Reset to the full width") { options.width = 100 }
                }

                LabeledContent("Height") {
                    VStack(alignment: .trailing, spacing: 4) {
                        Picker("Height", selection: Binding(
                            get: { options.height != nil },
                            set: { options.height = $0 ? (options.height ?? 480) : nil })) {
                            Text("Auto (4:3)").tag(false)
                            Text("Set").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        if let height = options.height {
                            NumberStepper(value: Binding(get: { Double(height) }, set: { options.height = Int($0) }),
                                          range: Double(ModelEmbed.Options.heights.lowerBound)...Double(ModelEmbed.Options.heights.upperBound),
                                          step: 20, isReset: false, resetHelp: "Back to Auto") { options.height = nil }
                        }
                    }
                }

                LabeledContent("Background") {
                    HStack(spacing: 8) {
                        Picker("Background", selection: backgroundChoice) {
                            Text("Card color").tag(BackgroundChoice.theme)
                            Text("Transparent").tag(BackgroundChoice.transparent)
                            Text("Color").tag(BackgroundChoice.color)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        if case .color = options.background {
                            ColorPicker("Color", selection: Binding(get: { color }, set: {
                                color = $0
                                options.background = .color(Self.hex($0))
                            }), supportsOpacity: false)
                            .labelsHidden()
                        }
                    }
                }

                Toggle("Spin slowly until someone touches it", isOn: $options.spin)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            Text(note)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Insert" : "Update") {
                    save(alt.trimmingCharacters(in: .whitespaces), options)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private var note: String {
        var parts = ["Card color uses Surface from Configuration → Colors; Transparent lets the page show through."]
        if options.width < 100 { parts.append("Narrower models are centered. Phones always show them at full width.") }
        parts.append("The preview shows your changes once you click \(isNew ? "Insert" : "Update").")
        return parts.joined(separator: " ")
    }

    /// `#rrggbb` for a color, in sRGB.
    static func hex(_ color: Color) -> String {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return "#ffffff" }
        let v = { (x: CGFloat) in Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", v(c.redComponent), v(c.greenComponent), v(c.blueComponent))
    }

    static func color(_ hex: String) -> Color? {
        var digits = String(hex.dropFirst())
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count >= 6, let n = UInt32(digits.prefix(6), radix: 16) else { return nil }
        return Color(.sRGB, red: Double((n >> 16) & 0xff) / 255, green: Double((n >> 8) & 0xff) / 255, blue: Double(n & 0xff) / 255)
    }
}
