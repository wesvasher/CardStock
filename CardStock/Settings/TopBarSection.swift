import SwiftUI

/// Configuration → Top Navigation Bar: how the bar at the top of every page
/// behaves, its logo, and its left, center and right groups of links. Saved
/// in site.json (`header`, and `nav` for the right-hand links).
struct TopBarSection: View {
    @Environment(AppModel.self) private var model
    @Binding var config: SiteConfig
    @State private var choosingCompact = false

    private typealias Mode = SiteConfig.Header.Mode
    private typealias Position = SiteConfig.Header.Position

    private var header: Binding<SiteConfig.Header> { $config.header }
    private var h: SiteConfig.Header { config.header }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Style")
                ChoiceCards(selection: header.mode, options: [
                    .init(value: Mode.scrolls, title: "Scrolls Away", systemImage: "menubar.arrow.up.rectangle",
                          help: "The bar scrolls away with the page"),
                    .init(value: Mode.fixed, title: "Fixed", systemImage: "pin.fill",
                          help: "The bar stays at the top of the window"),
                    .init(value: Mode.shrinking, title: "Shrinks on Scroll", systemImage: "rectangle.compress.vertical",
                          help: "The bar starts tall and shrinks as the page scrolls"),
                ])
            }

            if h.mode != .scrolls {
                LabeledContent("Bar height") {
                    NudgeSlider(value: number(\.height), range: 40...200)
                }
            }
            if h.mode == .shrinking {
                LabeledContent("Height after scrolling") {
                    NudgeSlider(value: number(\.compactHeight), range: 32...120)
                }
            }
        } header: {
            Text("Top Navigation Bar")
        } footer: {
            caption(explanation)
        }

        Section {
            Toggle(isOn: header.showLogo) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show logo")
                    if !h.showLogo {
                        Text("Off: the logo is hidden on your site. Its settings are kept.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .toggleStyle(.switch)
            LogoImageRows(image: header.logo, width: header.logoWidth, height: header.logoHeight,
                          sheetTitle: "Choose a Logo", startHeight: 40)
            if h.hasLogo {
                TextField("Description", text: header.logoAlt, prompt: Text(config.title))
                    .help("Read aloud by screen readers when the site title isn't shown. Leave empty to use the site title.")
            }
            Toggle(isOn: header.showTitle) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show site title")
                    Text("“\(config.title)”, next to the logo when both are on.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            Picker("Position", selection: header.logoPosition) {
                Text("Left").tag(Position.left)
                Text("Center").tag(Position.center)
                Text("Right").tag(Position.right)
            }
            .pickerStyle(.segmented)

            LabeledContent("Padding") {
                HStack(spacing: 10) {
                    paddingField("Top", \.top)
                    paddingField("Right", \.right)
                    paddingField("Bottom", \.bottom)
                    paddingField("Left", \.left)
                    Text("px").foregroundStyle(.secondary)
                }
            }

            if h.mode == .shrinking && h.hasLogo {
                compactLogoRow
                LabeledContent("Compact logo height") {
                    NudgeSlider(value: number(\.compactLogoHeight), range: 12...120)
                }
            }
        } header: {
            Text("Logo")
        } footer: {
            caption(!h.isLogoShown && !h.showTitle
                    ? "With the logo and the site title both off, the bar shows just its links."
                    : "The logo and site title sit together, before the links in their position (after them on the right). SVG logos stay sharp at every size.")
        }

        LinkGroupSection(title: "Left Links", toggleTitle: "Links on the left",
                         isOn: header.showLeftLinks, links: header.leftLinks)
        LinkGroupSection(title: "Center Links", toggleTitle: "Links in the center",
                         isOn: header.showCenterLinks, links: header.centerLinks)
        LinkGroupSection(title: "Right Links", toggleTitle: "Links on the right",
                         isOn: header.showRightLinks, links: $config.nav,
                         note: "Use addresses like /about/ for your own pages, or a full https:// address for other sites. Turn on any mix of groups, or none.")

        Section {
            Toggle(isOn: header.mobileMenu) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fold links into a menu on phones")
                    Text("On narrow screens, a menu button replaces the links and opens them over the whole page.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
        } header: {
            Text("Phones")
        } footer: {
            caption("To see it, pick a phone in the preview’s device menu. Off, the links stay in the bar and wrap onto more lines.")
        }

        Section {
            FontPicker(title: "Font", selection: theme(\.navFont), custom: model.webFonts,
                       emptyChoice: "Same as Headings")
            LabeledContent("Size") {
                NudgeSlider(value: theme(\.navSize), range: 10...28)
            }
            Picker("Weight", selection: theme(\.navWeight)) {
                Text("Regular").tag(400)
                Text("Semibold").tag(600)
                Text("Bold").tag(700)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Link Style")
        } footer: {
            caption("For the links in all three groups. Add more fonts on the Fonts page.")
        }

        Section {
            linkColorGrid
        } header: {
            Text("Link Colors")
        } footer: {
            caption("Colors you haven't picked follow the site's colors: links use Secondary text, hover and the current page use Text, clicking uses the hover color, and icons match their link. Click ↺ to go back to following them.")
        }

        buttonStyleSection
    }

    // MARK: - Button style

    private typealias NavButton = ThemeSettings.NavButton

    @ViewBuilder
    private var buttonStyleSection: some View {
        let button = (model.site?.theme ?? ThemeSettings()).navButton
        Section {
            buttonColorGrid
            LabeledContent("Border width") {
                NudgeSlider(value: theme(\.navButton.borderWidth), range: 0...6)
            }
            Picker("Corners", selection: theme(\.navButton.pill)) {
                Text("Rounded").tag(false)
                Text("Fully Round").tag(true)
            }
            .pickerStyle(.segmented)
            if !button.pill {
                LabeledContent("Corner radius") {
                    NudgeSlider(value: theme(\.navButton.radius), range: 0...24)
                }
            }
            LabeledContent("Background opacity") {
                NudgeSlider(value: theme(\.navButton.opacity), range: 0...100, step: 5, unit: "%")
            }
            LabeledContent("Background blur") {
                NudgeSlider(value: theme(\.navButton.blur), range: 0...30)
            }
            Picker("Shadow", selection: theme(\.navButton.shadow)) {
                Text("None").tag(ThemeSettings.Shadow.none)
                Text("Soft").tag(ThemeSettings.Shadow.soft)
                Text("Strong").tag(ThemeSettings.Shadow.strong)
            }
            .pickerStyle(.segmented)
            Picker("Icon position", selection: theme(\.navButton.iconPosition)) {
                Text("Before Text").tag(NavButton.IconPosition.left)
                Text("After Text").tag(NavButton.IconPosition.right)
            }
            .pickerStyle(.segmented)
            LabeledContent("Padding, sides") {
                NudgeSlider(value: theme(\.navButton.paddingX), range: 0...40)
            }
            LabeledContent("Padding, top and bottom") {
                NudgeSlider(value: theme(\.navButton.paddingY), range: 0...24)
            }
        } header: {
            Text("Button Style")
        } footer: {
            caption("For links with Button checked, in any group. Lower the background opacity and add blur for a frosted-glass button. Icon position applies to every top bar link with an icon.")
        }
    }

    private var buttonColorGrid: some View {
        let theme = model.site?.theme ?? ThemeSettings()
        let rows: [(String, WritableKeyPath<NavButton.Colors, String>)] = [
            ("Background", \.background),
            ("Text", \.text),
            ("Border", \.border),
            ("Icon", \.icon),
        ]
        return Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
            GridRow {
                Text("")
                Label("Light", systemImage: "sun.max.fill").font(.caption).foregroundStyle(.secondary)
                Label("Dark", systemImage: "moon.fill").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(rows, id: \.0) { row in
                GridRow {
                    Text(row.0)
                    colorCell(row.0, value: join(\.navButton.light, row.1),
                              shown: theme.navButton.light.resolved(theme.light)[keyPath: row.1])
                    colorCell(row.0, value: join(\.navButton.dark, row.1),
                              shown: theme.navButton.dark.resolved(theme.dark)[keyPath: row.1])
                }
            }
        }
        .controlSize(.small)
    }

    // MARK: - Link colors

    private typealias NavColors = ThemeSettings.NavColors

    private var linkColorGrid: some View {
        let theme = model.site?.theme ?? ThemeSettings()
        let rows: [(String, WritableKeyPath<NavColors, String>)] = [
            ("Links", \.link),
            ("Hover", \.hover),
            ("Current page", \.current),
            ("Click", \.pressed),
            ("Icons", \.icon),
        ]
        return Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
            GridRow {
                Text("")
                Label("Light", systemImage: "sun.max.fill").font(.caption).foregroundStyle(.secondary)
                Label("Dark", systemImage: "moon.fill").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(rows, id: \.0) { row in
                GridRow {
                    Text(row.0)
                    colorCell(row.0, value: join(\.navLight, row.1),
                              shown: theme.navLight.resolved(theme.light)[keyPath: row.1])
                    colorCell(row.0, value: join(\.navDark, row.1),
                              shown: theme.navDark.resolved(theme.dark)[keyPath: row.1])
                }
            }
        }
        .controlSize(.small)
    }

    /// One color in one appearance: a swatch that opens the color picker,
    /// its hex value to type in, and ↺ when it's been picked. `value` is the
    /// stored hex (empty follows the palette); `shown` is what it looks like.
    private func colorCell(_ title: String, value: WritableKeyPath<ThemeSettings, String>, shown: String) -> some View {
        let stored = (model.site?.theme ?? ThemeSettings())[keyPath: value]
        let isSet = !stored.isEmpty
        return HStack(spacing: 3) {
            ColorPicker(title, selection: Binding(
                get: { Color(hex: shown) ?? .gray },
                set: { color in updateTheme { $0[keyPath: value] = color.hexString } }),
                        supportsOpacity: false)
                .labelsHidden()
                .help("Click to pick a color")
            HexField(value: stored, placeholder: shown) { hex in
                updateTheme { $0[keyPath: value] = hex }
            }
            Button {
                updateTheme { $0[keyPath: value] = "" }
            } label: {
                Image(systemName: "arrow.counterclockwise").font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Follow the site's colors")
            .opacity(isSet ? 1 : 0)
            .disabled(!isSet)
        }
    }

    /// A color inside one of the theme's color groups, as a writable path.
    private func join<Group>(_ group: WritableKeyPath<ThemeSettings, Group>,
                             _ color: WritableKeyPath<Group, String>) -> WritableKeyPath<ThemeSettings, String> {
        group.appending(path: color)
    }

    private func updateTheme(_ change: (inout ThemeSettings) -> Void) {
        var updated = model.site?.theme ?? ThemeSettings()
        change(&updated)
        model.updateTheme(updated)
    }

    /// A theme.json setting, saved like the Fonts page's.
    private func theme<T>(_ keyPath: WritableKeyPath<ThemeSettings, T>) -> Binding<T> {
        Binding(
            get: { (model.site?.theme ?? ThemeSettings())[keyPath: keyPath] },
            set: { value in
                var updated = model.site?.theme ?? ThemeSettings()
                updated[keyPath: keyPath] = value
                model.updateTheme(updated)
            })
    }

    private var explanation: String {
        switch h.mode {
        case .scrolls:
            "The bar is part of the page and scrolls away with it."
        case .fixed:
            "The bar stays at the top of the window, the same size, and the page scrolls behind it with a soft blur."
        case .shrinking:
            "The bar starts tall and shrinks smoothly as the page scrolls, with the page blurred behind it. Add a compact logo below to switch to a smaller design, such as just an icon."
        }
    }

    // MARK: - Rows

    private var compactLogoRow: some View {
        LabeledContent("Compact logo") {
            HStack(spacing: 8) {
                if h.compactLogo.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Uses the main logo, scaled down").foregroundStyle(.secondary)
                    Button("Choose…") { choosingCompact = true }
                } else {
                    Text(h.compactLogo)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Change…") { choosingCompact = true }
                    Button("Remove") { config.header.compactLogo = "" }
                }
            }
        }
        .sheet(isPresented: $choosingCompact) {
            InsertFromFilesSheet(title: "Choose a Compact Logo",
                                 message: "Pick an image from your site's Files, or choose one from your Mac to copy it in.",
                                 actionTitle: "Choose",
                                 allowsMacFiles: true) { file in
                config.header.compactLogo = "/" + file.path
            }
        }
    }

    private func paddingField(_ label: String, _ side: WritableKeyPath<SiteConfig.Header.Padding, Int>) -> some View {
        VStack(spacing: 2) {
            PixelField(label: "Padding \(label.lowercased())", value: Binding(
                get: { config.header.logoPadding[keyPath: side] },
                set: { config.header.logoPadding[keyPath: side] = max($0, 0) }), width: 52)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// An Int setting as a Double, for the sliders.
    private func number(_ keyPath: WritableKeyPath<SiteConfig.Header, Int>) -> Binding<Double> {
        Binding(get: { Double(config.header[keyPath: keyPath]) },
                set: { config.header[keyPath: keyPath] = Int($0.rounded()) })
    }
}

/// One of the top bar's link groups: a switch to show it on the site, then
/// its links, which stay listed (and editable) while it's off.
struct LinkGroupSection: View {
    let title: String
    let toggleTitle: String
    @Binding var isOn: Bool
    @Binding var links: [SiteConfig.NavLink]
    var note: String?

    var body: some View {
        Section {
            Toggle(isOn: $isOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(toggleTitle)
                    if !isOn && !links.isEmpty {
                        Text("Off: these links aren't shown on your site.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .toggleStyle(.switch)
            ForEach(links.indices, id: \.self) { i in
                LinkRow(links: $links, index: i, addressPrompt: "/about/", topBarOptions: true)
            }
            Button("Add Link") {
                links.append(.init(title: "New Link", url: "/"))
            }
        } header: {
            Text(title)
        } footer: {
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A hex color typed in, such as #1d1d1f (the # and short #rgb forms work
/// too). Empty means "follow the site's colors", shown as the placeholder.
/// Bad values go back to what was there.
private struct HexField: View {
    let value: String
    let placeholder: String
    let onCommit: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Hex", text: $text, prompt: Text(placeholder))
            .labelsHidden()
            .font(.caption.monospaced())
            .frame(width: 66)
            .focused($focused)
            .onAppear { text = value }
            .onChange(of: value) { _, new in if !focused { text = new } }
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            .onSubmit(commit)
            .help("Hex color, such as #1d1d1f. Leave empty to follow the site's colors.")
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            onCommit("")
            return
        }
        var hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard [3, 6].contains(hex.count), hex.allSatisfy(\.isHexDigit) else {
            text = value
            return
        }
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        let normalized = "#" + hex.lowercased()
        text = normalized
        onCommit(normalized)
    }
}
