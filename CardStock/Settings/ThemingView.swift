import AppKit
import SwiftUI

/// One look page of Configuration (templates, fonts, colors, top bar, footer
/// or components). Fills the right column.
struct ThemingView: View {
    @Environment(AppModel.self) private var model
    let page: ConfigPage
    @State private var confirmReset = false
    @State private var showAddFont = false
    @State private var fontToRemove: ThemeSettings.CustomFont?

    private var theme: ThemeSettings { model.site?.theme ?? ThemeSettings() }

    private var themeUpdateExplanation: String {
        var reasons: [String] = []
        if model.outdatedThemeFiles.contains("theme/assets/style.css") {
            reasons.append("newer features (fonts, text and heading sizes, components, the top bar's link groups and fine print) need the updated stylesheet")
        }
        if model.outdatedThemeFiles.contains("theme/base.html") {
            reasons.append("the top bar and footer settings need the updated page template")
        }
        if model.outdatedThemeFiles.contains("theme/template.html") {
            reasons.append("the Template page needs the updated version to show images and menus")
        }
        if SiteRenderer.newerTemplateNames.contains(where: { model.outdatedThemeFiles.contains("theme/\($0).html") }) {
            reasons.append("collections and tag pages need their page templates (until then CardStock uses its own)")
        }
        if model.outdatedThemeFiles.contains("theme/home.html") {
            reasons.append("the home page needs the updated template to show your Home page text")
        }
        let files = model.outdatedThemeFiles.joined(separator: " and ")
        return reasons.joined(separator: ", and ").prefix(1).uppercased()
            + reasons.joined(separator: ", and ").dropFirst()
            + ". Updating replaces \(files) with the current defaults. The old files go to your Mac's Trash."
    }

    private var configBinding: Binding<SiteConfig> {
        Binding(
            get: { model.site?.config ?? SiteConfig() },
            set: { model.updateConfig($0) })
    }

    var body: some View {
        Form {
            if !model.outdatedThemeFiles.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Some theme files are out of date", systemImage: "exclamationmark.triangle")
                            .font(.headline)
                        Text(themeUpdateExplanation)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Update Theme Files") { model.updateThemeFiles() }
                    }
                    .padding(.vertical, 4)
                }
            }

            switch page {
            case .site, .layouts, .collections, .folders, .tags:
                EmptyView()
            case .templates:
                StylesSection()
                Section {
                    Button("Reset to Defaults…") { confirmReset = true }
                        .disabled(model.site?.theme == nil || model.site?.theme == ThemeSettings())
                } footer: {
                    Text("Fonts, colors and layout are saved in theme/theme.json in the site folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .fonts:
                Section("Fonts") {
                    FontPicker(title: "Body text", selection: binding(\.bodyFont), custom: model.webFonts)
                    FontPicker(title: "Headings", selection: binding(\.headingFont), custom: model.webFonts)
                    LabeledContent("Text size") {
                        NudgeSlider(value: binding(\.fontSize), range: 14...24)
                    }
                    LabeledContent("Heading (H1) size") {
                        NudgeSlider(value: binding(\.h1Size), range: 20...72)
                    }
                    webFontRows
                }
            case .colors:
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Appearance")
                        AppearanceCards(selection: binding(\.appearance))
                    }
                    paletteGrid
                } header: {
                    Text("Colors")
                } footer: {
                    if theme.appearance == .auto {
                        Text("Visitors see the light or dark colors depending on their device's setting.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            case .topBar:
                TopBarSection(config: configBinding)
            case .footer:
                FooterSection(config: configBinding)
            case .components:
                ComponentsSection(theme: Binding(get: { theme }, set: { model.updateTheme($0) }))
            case .newsletter:
                NewsletterSection(config: configBinding)
            case .search:
                SearchSection(config: configBinding)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showAddFont) {
            AddWebFontSheet()
        }
        .confirmationDialog("Remove this web font?", isPresented: Binding(
            get: { fontToRemove != nil }, set: { if !$0 { fontToRemove = nil } }), presenting: fontToRemove) { font in
            Button("Remove “\(font.family)”", role: .destructive) { model.removeWebFont(font) }
        } message: { _ in
            Text("It's removed from this site's font menus. Body text or headings using it switch back to the default font.")
        }
        .confirmationDialog("Reset fonts, colors and components to the defaults?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { model.updateTheme(ThemeSettings()) }
        } message: {
            Text("Fonts, colors and components go back to CardStock's defaults.")
        }
    }

    /// "Web fonts" with an Add button, then one row per font added to the site.
    @ViewBuilder
    private var webFontRows: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Web fonts")
                Text(model.webFonts.isEmpty
                     ? "Add fonts from Google Fonts, Adobe Fonts and others."
                     : "Saved with this site in theme/fonts.json.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Add…") { showAddFont = true }
        }
        ForEach(model.webFonts) { font in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(font.family)
                    Text(URL(string: font.url)?.host() ?? font.url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 12)
                Spacer()
                Picker("Style", selection: Binding(
                    get: { model.webFonts.first { $0.id == font.id }?.style ?? .sans },
                    set: { model.setWebFontStyle(font, $0) })) {
                    Text("Sans serif").tag(ThemeSettings.CustomFont.Style.sans)
                    Text("Serif").tag(ThemeSettings.CustomFont.Style.serif)
                    Text("Monospace").tag(ThemeSettings.CustomFont.Style.mono)
                }
                .labelsHidden()
                .fixedSize()
                .help("Which kind of font to show while this one loads")
                Button { fontToRemove = font } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                    .help("Remove from this site")
            }
        }
    }

    private var paletteGrid: some View {
        let rows: [(String, WritableKeyPath<ThemeSettings.Palette, String>)] = [
            ("Background", \.background),
            ("Cards and code blocks", \.surface),
            ("Text", \.text),
            ("Secondary text", \.muted),
            ("Accent and links", \.accent),
            ("Lines and borders", \.line),
        ]
        let showLight = theme.appearance != .dark
        let showDark = theme.appearance != .light
        return Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                Text("")
                if showLight { Text("Light").font(.caption).foregroundStyle(.secondary) }
                if showDark { Text("Dark").font(.caption).foregroundStyle(.secondary) }
            }
            ForEach(rows, id: \.0) { row in
                GridRow {
                    Text(row.0)
                    if showLight {
                        ColorPicker(row.0, selection: color(\.light, row.1), supportsOpacity: false)
                            .labelsHidden()
                    }
                    if showDark {
                        ColorPicker(row.0, selection: color(\.dark, row.1), supportsOpacity: false)
                            .labelsHidden()
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Bindings

    private func binding<T>(_ keyPath: WritableKeyPath<ThemeSettings, T>) -> Binding<T> {
        Binding(
            get: { theme[keyPath: keyPath] },
            set: { newValue in
                var updated = theme
                updated[keyPath: keyPath] = newValue
                model.updateTheme(updated)
            })
    }

    private func color(_ palette: WritableKeyPath<ThemeSettings, ThemeSettings.Palette>,
                       _ key: WritableKeyPath<ThemeSettings.Palette, String>) -> Binding<Color> {
        Binding(
            get: { Color(hex: theme[keyPath: palette][keyPath: key]) ?? .gray },
            set: { newValue in
                var updated = theme
                updated[keyPath: palette][keyPath: key] = newValue.hexString
                model.updateTheme(updated)
            })
    }
}

/// A menu of the available fonts, grouped by style.
struct FontPicker: View {
    let title: String
    @Binding var selection: String
    let custom: [ThemeSettings.CustomFont]
    /// Adds a first choice with an empty id, e.g. "Same as Headings".
    var emptyChoice: String?

    var body: some View {
        Picker(title, selection: $selection) {
            if let emptyChoice {
                Text(emptyChoice).tag("")
                Divider()
            }
            if !custom.isEmpty {
                Section("Web Fonts") {
                    ForEach(custom) { font in
                        Text(font.family).tag(font.id)
                    }
                }
            }
            ForEach(ThemeFont.Category.allCases, id: \.self) { category in
                Section(category.rawValue) {
                    ForEach(ThemeFont.all.filter { $0.category == category }) { font in
                        Text(font.name).tag(font.id)
                    }
                }
            }
        }
    }
}

extension Color {
    /// Parses `#rgb` or `#rrggbb`.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        guard s.hasPrefix("#") else { return nil }
        s.removeFirst()
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xff) / 255,
                  green: Double((value >> 8) & 0xff) / 255,
                  blue: Double(value & 0xff) / 255)
    }

    /// `#rrggbb` in sRGB.
    var hexString: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "#000000" }
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }
}
