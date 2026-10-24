import Foundation

/// Look-and-feel choices from `theme/theme.json`. CardStock turns them into
/// CSS variables added to every page, overriding the theme's defaults.
struct ThemeSettings: Codable, Equatable, Sendable {
    enum Appearance: String, Codable, CaseIterable, Sendable {
        case auto, light, dark
    }

    struct Palette: Codable, Equatable, Sendable {
        var background: String
        var surface: String
        var text: String
        var muted: String
        var accent: String
        var line: String

        static let light = Palette(background: "#fdfcfa", surface: "#ffffff", text: "#1d1d1f",
                                   muted: "#6e6e73", accent: "#b4532a", line: "#e5e3df")
        static let dark = Palette(background: "#161617", surface: "#1f1f21", text: "#ececec",
                                  muted: "#9a9aa0", accent: "#f08a5d", line: "#2e2e30")
    }

    /// Fonts added by URL in the Theming panel.
    struct CustomFont: Codable, Equatable, Sendable, Identifiable {
        enum Style: String, Codable, CaseIterable, Sendable {
            case sans, serif, mono

            var fallback: String {
                switch self {
                case .sans: "system-ui, sans-serif"
                case .serif: "Georgia, serif"
                case .mono: "ui-monospace, monospace"
                }
            }
        }

        var family: String
        /// A stylesheet URL, or a direct link to a font file.
        var url: String
        var style: Style

        var id: String { "custom:" + family }

        var isFontFile: Bool {
            let path = URL(string: url)?.path.lowercased() ?? ""
            return ["woff2", "woff", "ttf", "otf"].contains((path as NSString).pathExtension)
        }

        var stack: String { "\"\(ThemeSettings.cssString(family))\", \(style.fallback)" }

        init(family: String, url: String, style: Style) {
            self.family = family
            self.url = url
            self.style = style
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            family = try c.decode(String.self, forKey: .family)
            url = try c.decode(String.self, forKey: .url)
            style = try c.decodeIfPresent(Style.self, forKey: .style) ?? .sans
        }
    }

    var bodyFont = "system-serif"
    var headingFont = "system-sans"
    /// Base text size in pixels.
    var fontSize: Double = 18
    /// Main heading (H1) size in pixels.
    var h1Size: Double = 32
    var appearance = Appearance.auto
    var light = Palette.light
    var dark = Palette.dark
    /// Corner radius in pixels: the starting point for each component's
    /// corners (Configuration → Components → Apply to All).
    var radius: Double = 8
    /// Width of the text column in rem.
    var contentWidth: Double = 40
    var customFonts: [CustomFont] = []

    // Components. Corner radii default to `radius` times each one's
    // `RadiusShare`, which is how the theme looked before they existed.

    enum ButtonStyle: String, Codable, CaseIterable, Sendable {
        /// Accent outline, accent text.
        case outline
        /// Accent background, page-colored text.
        case filled
    }

    enum Shadow: String, Codable, CaseIterable, Sendable {
        case none, soft, strong
    }

    enum QuoteColor: String, Codable, CaseIterable, Sendable {
        case line, accent
    }

    /// How each component's corners compare to `radius`, as the theme had them.
    enum RadiusShare {
        static let button = 0.75
        static let card = 1.25
        static let cover = 1.0
        static let code = 1.0
        static let menu = 1.0
    }

    var buttonStyle = ButtonStyle.outline
    var buttonRadius: Double = 6
    /// Space inside buttons, in pixels.
    var buttonPaddingX: Double = 16
    var buttonPaddingY: Double = 8

    var cardRadius: Double = 10
    var cardPadding: Double = 20
    var cardBorder = true
    var cardShadow = Shadow.none

    /// Cover images at the top of pages.
    var coverRadius: Double = 8
    /// Images in a page's text.
    var imageRadius: Double = 0

    var codeRadius: Double = 8

    var quoteColor = QuoteColor.line
    var quoteBarWidth: Double = 3

    /// Shades every other row of tables.
    var tableStripes = false

    /// Drop-down menus, such as the footer's.
    var menuRadius: Double = 8

    // Top bar links (Configuration → Top Navigation Bar → Link Style).

    /// Font for the top bar's links. Empty uses the headings font.
    var navFont = ""
    /// Text size of the top bar's links, in pixels.
    var navSize: Double = 15
    /// 400 regular, 600 semibold or 700 bold: the weights loaded for Google Fonts.
    var navWeight = 400
    /// Top bar link colors for light and dark appearance.
    var navLight = NavColors()
    var navDark = NavColors()
    /// How top bar links marked as buttons look, and where every top bar
    /// link's icon goes.
    var navButton = NavButton()

    /// The look of top bar buttons. Colors are `#rrggbb` per appearance;
    /// empty follows the palette (accent background, page-colored text,
    /// line-colored border).
    struct NavButton: Codable, Equatable, Sendable {
        struct Colors: Codable, Equatable, Sendable {
            var background = ""
            var text = ""
            var border = ""
            /// Icons on buttons. Empty uses the button's text color.
            var icon = ""

            init() {}

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                background = try c.decodeIfPresent(String.self, forKey: .background) ?? ""
                text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
                border = try c.decodeIfPresent(String.self, forKey: .border) ?? ""
                icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? ""
            }

            /// The color each part shows with `palette`.
            func resolved(_ palette: Palette) -> Colors {
                var r = Colors()
                r.background = background.isEmpty ? palette.accent : background
                r.text = text.isEmpty ? palette.background : text
                r.border = border.isEmpty ? palette.line : border
                r.icon = icon.isEmpty ? r.text : icon
                return r
            }
        }

        enum IconPosition: String, Codable, CaseIterable, Sendable {
            case left, right
        }

        var light = Colors()
        var dark = Colors()
        var borderWidth: Double = 0
        var radius: Double = 8
        /// Fully round ends, whatever the radius.
        var pill = false
        /// Background opacity, 0–100 %.
        var opacity: Double = 100
        /// Blur of whatever shows through the background, in pixels.
        var blur: Double = 0
        var shadow = Shadow.none
        /// Icon before or after the text, for links and buttons.
        var iconPosition = IconPosition.left
        var paddingX: Double = 14
        var paddingY: Double = 6

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = NavButton()
            light = try c.decodeIfPresent(Colors.self, forKey: .light) ?? d.light
            dark = try c.decodeIfPresent(Colors.self, forKey: .dark) ?? d.dark
            borderWidth = try c.decodeIfPresent(Double.self, forKey: .borderWidth) ?? d.borderWidth
            radius = try c.decodeIfPresent(Double.self, forKey: .radius) ?? d.radius
            pill = try c.decodeIfPresent(Bool.self, forKey: .pill) ?? d.pill
            opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? d.opacity
            blur = try c.decodeIfPresent(Double.self, forKey: .blur) ?? d.blur
            shadow = (try? c.decodeIfPresent(Shadow.self, forKey: .shadow)) ?? d.shadow
            iconPosition = (try? c.decodeIfPresent(IconPosition.self, forKey: .iconPosition)) ?? d.iconPosition
            paddingX = try c.decodeIfPresent(Double.self, forKey: .paddingX) ?? d.paddingX
            paddingY = try c.decodeIfPresent(Double.self, forKey: .paddingY) ?? d.paddingY
        }
    }

    /// Colors of the top bar's links in each state, as `#rrggbb`. Empty
    /// follows the palette: links use secondary text, hover and the current
    /// page use text, and clicking uses the hover color.
    struct NavColors: Codable, Equatable, Sendable {
        var link = ""
        var hover = ""
        var current = ""
        var pressed = ""
        /// Icons on links. Empty uses the link's own color.
        var icon = ""

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            link = try c.decodeIfPresent(String.self, forKey: .link) ?? ""
            hover = try c.decodeIfPresent(String.self, forKey: .hover) ?? ""
            current = try c.decodeIfPresent(String.self, forKey: .current) ?? ""
            pressed = try c.decodeIfPresent(String.self, forKey: .pressed) ?? ""
            icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? ""
        }

        /// The color each state shows with `palette`.
        func resolved(_ palette: Palette) -> NavColors {
            var r = NavColors()
            r.link = link.isEmpty ? palette.muted : link
            r.hover = hover.isEmpty ? palette.text : hover
            r.current = current.isEmpty ? palette.text : current
            r.pressed = pressed.isEmpty ? r.hover : pressed
            r.icon = icon.isEmpty ? r.link : icon
            return r
        }
    }

    static let fileName = "theme/theme.json"

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ThemeSettings()
        bodyFont = try c.decodeIfPresent(String.self, forKey: .bodyFont) ?? d.bodyFont
        headingFont = try c.decodeIfPresent(String.self, forKey: .headingFont) ?? d.headingFont
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? d.fontSize
        h1Size = try c.decodeIfPresent(Double.self, forKey: .h1Size) ?? d.h1Size
        appearance = try c.decodeIfPresent(Appearance.self, forKey: .appearance) ?? d.appearance
        light = try c.decodeIfPresent(Palette.self, forKey: .light) ?? d.light
        dark = try c.decodeIfPresent(Palette.self, forKey: .dark) ?? d.dark
        radius = try c.decodeIfPresent(Double.self, forKey: .radius) ?? d.radius
        contentWidth = try c.decodeIfPresent(Double.self, forKey: .contentWidth) ?? d.contentWidth
        customFonts = try c.decodeIfPresent([CustomFont].self, forKey: .customFonts) ?? []

        // Settings saved before Components follow the old single radius.
        let r = radius
        buttonStyle = (try? c.decodeIfPresent(ButtonStyle.self, forKey: .buttonStyle)) ?? d.buttonStyle
        buttonRadius = try c.decodeIfPresent(Double.self, forKey: .buttonRadius) ?? r * RadiusShare.button
        buttonPaddingX = try c.decodeIfPresent(Double.self, forKey: .buttonPaddingX) ?? d.buttonPaddingX
        buttonPaddingY = try c.decodeIfPresent(Double.self, forKey: .buttonPaddingY) ?? d.buttonPaddingY
        cardRadius = try c.decodeIfPresent(Double.self, forKey: .cardRadius) ?? r * RadiusShare.card
        cardPadding = try c.decodeIfPresent(Double.self, forKey: .cardPadding) ?? d.cardPadding
        cardBorder = try c.decodeIfPresent(Bool.self, forKey: .cardBorder) ?? d.cardBorder
        cardShadow = (try? c.decodeIfPresent(Shadow.self, forKey: .cardShadow)) ?? d.cardShadow
        coverRadius = try c.decodeIfPresent(Double.self, forKey: .coverRadius) ?? r * RadiusShare.cover
        imageRadius = try c.decodeIfPresent(Double.self, forKey: .imageRadius) ?? d.imageRadius
        codeRadius = try c.decodeIfPresent(Double.self, forKey: .codeRadius) ?? r * RadiusShare.code
        quoteColor = (try? c.decodeIfPresent(QuoteColor.self, forKey: .quoteColor)) ?? d.quoteColor
        quoteBarWidth = try c.decodeIfPresent(Double.self, forKey: .quoteBarWidth) ?? d.quoteBarWidth
        tableStripes = try c.decodeIfPresent(Bool.self, forKey: .tableStripes) ?? d.tableStripes
        menuRadius = try c.decodeIfPresent(Double.self, forKey: .menuRadius) ?? r * RadiusShare.menu
        navFont = try c.decodeIfPresent(String.self, forKey: .navFont) ?? d.navFont
        navSize = try c.decodeIfPresent(Double.self, forKey: .navSize) ?? d.navSize
        navWeight = try c.decodeIfPresent(Int.self, forKey: .navWeight) ?? d.navWeight
        navLight = try c.decodeIfPresent(NavColors.self, forKey: .navLight) ?? NavColors()
        navDark = try c.decodeIfPresent(NavColors.self, forKey: .navDark) ?? NavColors()
        navButton = try c.decodeIfPresent(NavButton.self, forKey: .navButton) ?? NavButton()
    }

    /// Sets every component's corners from `radius`.
    mutating func applyRadiusToAll() {
        buttonRadius = (radius * RadiusShare.button).rounded()
        cardRadius = (radius * RadiusShare.card).rounded()
        coverRadius = (radius * RadiusShare.cover).rounded()
        codeRadius = (radius * RadiusShare.code).rounded()
        menuRadius = (radius * RadiusShare.menu).rounded()
    }

    /// nil when the site has no theme.json (the theme's own CSS is used as is).
    static func load(from root: URL) -> ThemeSettings? {
        guard let data = try? Data(contentsOf: root.appending(path: fileName)) else { return nil }
        return try? JSONDecoder().decode(ThemeSettings.self, from: data)
    }

    func save(to root: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: root.appending(path: Self.fileName), options: .atomic)
    }

    // MARK: - CSS

    /// These settings with extra web fonts available (the site's fonts.json),
    /// so pages can load whichever ones are in use.
    func including(_ webFonts: [CustomFont]) -> ThemeSettings {
        var copy = self
        for font in webFonts where !copy.customFonts.contains(where: { $0.id == font.id }) {
            copy.customFonts.append(font)
        }
        return copy
    }

    /// The look alone, without the list of web fonts it carries. Used to
    /// compare a site's theming with saved styles.
    var look: ThemeSettings {
        var copy = self
        copy.customFonts = []
        return copy
    }

    /// The fonts in use: body text, headings and (when set) top bar links.
    var fontIDs: [String] { [bodyFont, headingFont] + (navFont.isEmpty ? [] : [navFont]) }

    /// The web fonts these settings actually use.
    func usedFonts(from fonts: [CustomFont]) -> [CustomFont] {
        fonts.filter { fontIDs.contains($0.id) }
    }

    /// CSS font stack for a font id (built-in, Google or custom).
    func stack(for id: String) -> String {
        ThemeFont.named(id)?.stack
            ?? customFonts.first { $0.id == id }?.stack
            ?? ThemeFont.all[0].stack
    }

    private var usedCustomFonts: [CustomFont] {
        customFonts.filter { fontIDs.contains($0.id) }
    }

    /// The `<link>` and `<style>` tags added to each page's `<head>`.
    var headHTML: String {
        var html = ""
        let google = fontIDs.compactMap { ThemeFont.named($0)?.googleFamily }
        if !google.isEmpty {
            let families = Array(Set(google)).sorted()
                .map { "family=" + $0.replacingOccurrences(of: " ", with: "+") + ":ital,wght@0,400;0,600;0,700;1,400" }
                .joined(separator: "&amp;")
            html += """
            <link rel="preconnect" href="https://fonts.googleapis.com">
            <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
            <link rel="stylesheet" href="https://fonts.googleapis.com/css2?\(families)&amp;display=swap">

            """
        }
        var linked = Set<String>()
        for font in usedCustomFonts where !font.isFontFile && linked.insert(font.url).inserted {
            html += "<link rel=\"stylesheet\" href=\"\(escapeHTML(font.url))\">\n"
        }
        html += "<style id=\"cardstock-theme\">\n\(css)</style>\n"
        return html
    }

    /// `@font-face` rules for custom fonts that link straight to a font file.
    private var fontFaces: String {
        usedCustomFonts.filter(\.isFontFile).map { font in
            let ext = (URL(string: font.url)?.path.lowercased() as NSString?)?.pathExtension ?? ""
            let format = ["woff2": "woff2", "woff": "woff", "ttf": "truetype", "otf": "opentype"][ext] ?? "woff2"
            return """
            @font-face {
              font-family: "\(Self.cssString(font.family))";
              src: url("\(Self.cssString(font.url))") format("\(format)");
              font-display: swap;
            }

            """
        }.joined()
    }

    /// Makes text safe inside a double-quoted CSS string.
    static func cssString(_ s: String) -> String {
        s.filter { !"\"\\<>{};\n\r".contains($0) }
    }

    var css: String {
        let body = stack(for: bodyFont)
        let heading = stack(for: headingFont)
        var css = fontFaces + ":root {\n"
        css += "  --font-body: \(body);\n"
        css += "  --font-heading: \(heading);\n"
        css += "  --font-size: \(Self.number(fontSize))px;\n"
        css += "  --h1-size: \(Self.number(h1Size))px;\n"
        css += "  --radius: \(Self.number(radius))px;\n"
        css += "  --measure: \(Self.number(contentWidth))rem;\n"
        css += componentVars
        switch appearance {
        case .auto:
            css += "  color-scheme: light dark;\n" + Self.vars(light) + Self.navVars(navLight) + Self.buttonVars(navButton.light) + "}\n"
            css += "@media (prefers-color-scheme: dark) {\n  :root {\n"
            css += Self.vars(dark, indent: "    ") + Self.navVars(navDark, indent: "    ")
                + Self.buttonVars(navButton.dark, indent: "    ") + "  }\n}\n"
        case .light:
            css += "  color-scheme: light;\n" + Self.vars(light) + Self.navVars(navLight) + Self.buttonVars(navButton.light) + "}\n"
        case .dark:
            css += "  color-scheme: dark;\n" + Self.vars(dark) + Self.navVars(navDark) + Self.buttonVars(navButton.dark) + "}\n"
        }
        return css
    }

    static func shadowValue(_ shadow: Shadow) -> String {
        switch shadow {
        case .none: "none"
        case .soft: "0 2px 10px rgba(0, 0, 0, 0.08)"
        case .strong: "0 10px 30px rgba(0, 0, 0, 0.18)"
        }
    }

    /// CSS variables for Configuration → Components, read by style.css.
    private var componentVars: String {
        func px(_ d: Double) -> String { "\(Self.number(max(d, 0)))px" }
        let shadow = Self.shadowValue(cardShadow)
        var lines: [(String, String)] = [
            ("nav-font", navFont.isEmpty ? "var(--font-heading)" : stack(for: navFont)),
            ("nav-size", px(navSize)),
            ("nav-weight", String([400, 600, 700].contains(navWeight) ? navWeight : 400)),
            ("navbtn-border-width", px(navButton.borderWidth)),
            ("navbtn-radius", navButton.pill ? "999px" : px(navButton.radius)),
            ("navbtn-alpha", "\(Self.number(min(max(navButton.opacity, 0), 100)))%"),
            ("navbtn-blur", px(navButton.blur)),
            ("navbtn-shadow", Self.shadowValue(navButton.shadow)),
            ("navbtn-pad-x", px(navButton.paddingX)),
            ("navbtn-pad-y", px(navButton.paddingY)),
            ("nav-icon-dir", navButton.iconPosition == .right ? "row-reverse" : "row"),
            ("button-radius", px(buttonRadius)),
            ("button-pad-x", px(buttonPaddingX)),
            ("button-pad-y", px(buttonPaddingY)),
            ("card-radius", px(cardRadius)),
            ("card-padding", px(cardPadding)),
            ("card-border", cardBorder ? "1px solid var(--line)" : "1px solid transparent"),
            ("card-shadow", shadow),
            ("cover-radius", px(coverRadius)),
            ("image-radius", px(imageRadius)),
            ("code-radius", px(codeRadius)),
            ("quote-bar", quoteColor == .accent ? "var(--accent)" : "var(--line)"),
            ("quote-bar-width", px(quoteBarWidth)),
            ("table-stripe", tableStripes ? "color-mix(in srgb, var(--text) 5%, transparent)" : "transparent"),
            ("menu-radius", px(menuRadius)),
        ]
        if buttonStyle == .filled {
            lines += [("button-bg", "var(--accent)"), ("button-text", "var(--bg)")]
        }
        return lines.map { "  --\($0.0): \($0.1);\n" }.joined()
    }

    private static func vars(_ p: Palette, indent: String = "  ") -> String {
        [("bg", p.background), ("card", p.surface), ("text", p.text),
         ("muted", p.muted), ("accent", p.accent), ("line", p.line)]
            .map { "\(indent)--\($0.0): \(sanitizeColor($0.1));\n" }
            .joined()
    }

    /// Top bar link colors; empty ones point at the palette's variables.
    private static func navVars(_ n: NavColors, indent: String = "  ") -> String {
        func value(_ s: String, _ fallback: String) -> String { s.isEmpty ? fallback : sanitizeColor(s) }
        return [("nav-link", value(n.link, "var(--muted)")),
                ("nav-hover", value(n.hover, "var(--text)")),
                ("nav-current", value(n.current, "var(--text)")),
                ("nav-pressed", value(n.pressed, "var(--nav-hover)")),
                ("nav-icon", value(n.icon, "currentColor"))]
            .map { "\(indent)--\($0.0): \($0.1);\n" }
            .joined()
    }

    /// Top bar button colors; empty ones point at the palette's variables.
    private static func buttonVars(_ c: NavButton.Colors, indent: String = "  ") -> String {
        func value(_ s: String, _ fallback: String) -> String { s.isEmpty ? fallback : sanitizeColor(s) }
        return [("navbtn-bg", value(c.background, "var(--accent)")),
                ("navbtn-text", value(c.text, "var(--bg)")),
                ("navbtn-border", value(c.border, "var(--line)")),
                ("navbtn-icon", value(c.icon, "currentColor"))]
            .map { "\(indent)--\($0.0): \($0.1);\n" }
            .joined()
    }

    private static func sanitizeColor(_ s: String) -> String {
        let ok = s.hasPrefix("#") && s.dropFirst().allSatisfy(\.isHexDigit) && [4, 7, 9].contains(s.count)
        return ok ? s : "inherit"
    }

    private static func number(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(format: "%.2f", d)
    }
}

/// A font choice offered in the Theming panel.
struct ThemeFont: Identifiable, Sendable {
    var id: String
    var name: String
    var stack: String
    /// Google Fonts family to load, or nil for fonts already on the device.
    var googleFamily: String?
    var category: Category

    enum Category: String, CaseIterable, Sendable {
        case system = "Built In"
        case sans = "Sans Serif"
        case serif = "Serif"
        case display = "Display"
        case mono = "Monospace"
    }

    static func named(_ id: String) -> ThemeFont? { all.first { $0.id == id } }

    private static func google(_ family: String, _ fallback: String, _ category: Category) -> ThemeFont {
        ThemeFont(id: family.lowercased().replacingOccurrences(of: " ", with: "-"), name: family,
                  stack: "\"\(family)\", \(fallback)", googleFamily: family, category: category)
    }

    static let all: [ThemeFont] = [
        ThemeFont(id: "system-sans", name: "System Sans", stack: "ui-sans-serif, -apple-system, system-ui, \"Segoe UI\", sans-serif", category: .system),
        ThemeFont(id: "system-serif", name: "System Serif", stack: "ui-serif, Georgia, \"Iowan Old Style\", serif", category: .system),
        ThemeFont(id: "system-rounded", name: "System Rounded", stack: "ui-rounded, \"SF Pro Rounded\", system-ui, sans-serif", category: .system),
        ThemeFont(id: "system-mono", name: "System Monospace", stack: "ui-monospace, \"SF Mono\", Menlo, Consolas, monospace", category: .system),
        google("Inter", "system-ui, sans-serif", .sans),
        google("DM Sans", "system-ui, sans-serif", .sans),
        google("IBM Plex Sans", "system-ui, sans-serif", .sans),
        google("Work Sans", "system-ui, sans-serif", .sans),
        google("Space Grotesk", "system-ui, sans-serif", .sans),
        google("Lora", "Georgia, serif", .serif),
        google("Merriweather", "Georgia, serif", .serif),
        google("Source Serif 4", "Georgia, serif", .serif),
        google("EB Garamond", "Georgia, serif", .serif),
        google("Libre Baskerville", "Georgia, serif", .serif),
        google("Playfair Display", "Georgia, serif", .display),
        google("Fraunces", "Georgia, serif", .display),
        google("JetBrains Mono", "ui-monospace, monospace", .mono),
        google("IBM Plex Mono", "ui-monospace, monospace", .mono),
    ]
}
