import SwiftUI

/// Configuration → Components: the look of each building
/// block of a page (buttons, cards, images, code blocks, quotes, tables and
/// drop-down menus). Saved in theme/theme.json as CSS variables.
struct ComponentsSection: View {
    @Binding var theme: ThemeSettings

    var body: some View {
        Section {
            LabeledContent("Corner radius") {
                NudgeSlider(value: $theme.radius, range: 0...24)
            }
            HStack {
                Spacer()
                Button("Apply Corners to All Components") {
                    withAnimation { theme.applyRadiusToAll() }
                }
                .help("Sets the corners of buttons, cards, cover images, code blocks and menus from this radius")
            }
        } header: {
            Text("Corners")
        } footer: {
            caption("The starting point for every component's corners; change each one below. Page width is on the Layout page.")
        }

        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Style")
                ChoiceCards(selection: $theme.buttonStyle, options: [
                    .init(value: .outline, title: "Outline", systemImage: "rectangle",
                          help: "Accent-colored border and text"),
                    .init(value: .filled, title: "Filled", systemImage: "rectangle.fill",
                          help: "Accent-colored background"),
                ])
            }
            LabeledContent("Corner radius") {
                NudgeSlider(value: $theme.buttonRadius, range: 0...30)
            }
            LabeledContent("Padding, sides") {
                NudgeSlider(value: $theme.buttonPaddingX, range: 4...40)
            }
            LabeledContent("Padding, top and bottom") {
                NudgeSlider(value: $theme.buttonPaddingY, range: 2...24)
            }
        } header: {
            Text("Buttons")
        } footer: {
            caption("Buttons in your pages. Buy buttons are always filled and a little bigger.")
        }

        Section {
            LabeledContent("Corner radius") {
                NudgeSlider(value: $theme.cardRadius, range: 0...32)
            }
            LabeledContent("Padding") {
                NudgeSlider(value: $theme.cardPadding, range: 0...48)
            }
            Toggle("Border", isOn: $theme.cardBorder)
                .toggleStyle(.switch)
            Picker("Shadow", selection: $theme.cardShadow) {
                Text("None").tag(ThemeSettings.Shadow.none)
                Text("Soft").tag(ThemeSettings.Shadow.soft)
                Text("Strong").tag(ThemeSettings.Shadow.strong)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Cards")
        } footer: {
            caption("Product cards in the shop and on shop categories.")
        }

        Section {
            LabeledContent("Cover images") {
                NudgeSlider(value: $theme.coverRadius, range: 0...32)
            }
            LabeledContent("Images in text") {
                NudgeSlider(value: $theme.imageRadius, range: 0...32)
            }
        } header: {
            Text("Image Corners")
        } footer: {
            caption("Cover images show at the top of pages and posts.")
        }

        Section("Code Blocks") {
            LabeledContent("Corner radius") {
                NudgeSlider(value: $theme.codeRadius, range: 0...24)
            }
        }

        Section("Quotes") {
            Picker("Line color", selection: $theme.quoteColor) {
                Text("Lines and borders").tag(ThemeSettings.QuoteColor.line)
                Text("Accent").tag(ThemeSettings.QuoteColor.accent)
            }
            LabeledContent("Line width") {
                NudgeSlider(value: $theme.quoteBarWidth, range: 0...10)
            }
        }

        Section("Tables") {
            Toggle("Shade every other row", isOn: $theme.tableStripes)
                .toggleStyle(.switch)
        }

        Section {
            LabeledContent("Corner radius") {
                NudgeSlider(value: $theme.menuRadius, range: 0...24)
            }
        } header: {
            Text("Drop-Down Menus")
        } footer: {
            caption("The lists of links that open from the footer's menu buttons.")
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
