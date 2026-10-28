import Foundation

/// Templates that come with CardStock, shown in Configuration → Templates
/// beside CardStock Default and the user's saved ones. Using one copies its
/// settings into the site's theme/theme.json, like a saved template.
struct BuiltInTemplate: Identifiable, Sendable {
    var id: String
    var name: String
    var summary: String
    var theme: ThemeSettings

    static func named(_ id: String) -> BuiltInTemplate? { all.first { $0.id == id } }

    /// Every component's corners from one radius, the way `radius` shares
    /// them out (Configuration → Components → Apply to All).
    private static func corners(_ t: inout ThemeSettings, _ r: Double) {
        typealias Share = ThemeSettings.RadiusShare
        t.radius = r
        t.buttonRadius = r * Share.button
        t.cardRadius = r * Share.card
        t.coverRadius = r * Share.cover
        t.codeRadius = r * Share.code
        t.menuRadius = r * Share.menu
        t.navButton.radius = r
    }

    private static func make(_ id: String, _ name: String, _ summary: String,
                             _ change: (inout ThemeSettings) -> Void) -> BuiltInTemplate {
        var theme = ThemeSettings()
        change(&theme)
        return BuiltInTemplate(id: id, name: name, summary: summary, theme: theme)
    }

    typealias Palette = ThemeSettings.Palette

    static let all: [BuiltInTemplate] = [
        make("journal", "Journal", "A warm, bookish serif for writing and essays.") { t in
            t.bodyFont = "lora"
            t.headingFont = "playfair-display"
            t.fontSize = 19
            t.h1Size = 42
            t.contentWidth = 45 // 720 px
            t.light = Palette(background: "#fbf7f0", surface: "#fffdf9", text: "#2b2622",
                              muted: "#7a6e64", accent: "#9c3d2a", line: "#e8dfd2")
            t.dark = Palette(background: "#1c1916", surface: "#24201c", text: "#ede6dc",
                             muted: "#a39889", accent: "#e08a6b", line: "#3a332c")
            corners(&t, 4)
            t.quoteColor = .accent
            t.quoteBarWidth = 3
            t.imageRadius = 2
        },
        make("studio", "Studio", "Bold, roomy sans serif for portfolios and products.") { t in
            t.bodyFont = "inter"
            t.headingFont = "space-grotesk"
            t.fontSize = 17
            t.h1Size = 48
            t.contentWidth = 71.25 // 1140 px
            t.gutter = 32
            t.light = Palette(background: "#ffffff", surface: "#f5f6f8", text: "#111318",
                              muted: "#5f6573", accent: "#2f5bff", line: "#e6e8ec")
            t.dark = Palette(background: "#0e0f12", surface: "#17191e", text: "#f1f2f5",
                             muted: "#9097a6", accent: "#7d97ff", line: "#262932")
            corners(&t, 12)
            t.buttonStyle = .filled
            t.buttonPaddingX = 20
            t.buttonPaddingY = 10
            t.cardBorder = false
            t.cardShadow = .soft
            t.cardPadding = 24
            t.imageRadius = 12
            t.fullWidthHeader = true
            t.fullWidthFooter = true
            t.navWeight = 600
            t.navButton.pill = true
        },
        make("editorial", "Editorial", "Classic newspaper serif with crisp, square edges.") { t in
            t.bodyFont = "source-serif-4"
            t.headingFont = "libre-baskerville"
            t.fontSize = 18
            t.h1Size = 40
            t.contentWidth = 48 // 768 px
            t.light = Palette(background: "#ffffff", surface: "#f7f7f5", text: "#121212",
                              muted: "#5c5c5c", accent: "#1f5f4a", line: "#dcdcd8")
            t.dark = Palette(background: "#121313", surface: "#1a1b1b", text: "#e9e9e6",
                             muted: "#a0a09b", accent: "#6cc3a0", line: "#2c2d2c")
            corners(&t, 0)
            t.quoteColor = .accent
            t.quoteBarWidth = 4
            t.tableStripes = true
            t.navFont = "system-sans"
            t.navSize = 13
            t.navWeight = 600
        },
        make("night", "Night", "A dark, modern sans serif that's easy on the eyes.") { t in
            t.bodyFont = "dm-sans"
            t.headingFont = "dm-sans"
            t.fontSize = 17
            t.h1Size = 40
            t.contentWidth = 60 // 960 px
            t.appearance = .dark
            t.light = Palette(background: "#f7f8fb", surface: "#ffffff", text: "#151821",
                              muted: "#5d6475", accent: "#4a63e0", line: "#e2e5ee")
            t.dark = Palette(background: "#0f1115", surface: "#171a21", text: "#e6e8ee",
                             muted: "#8b93a7", accent: "#7c9cff", line: "#262b36")
            corners(&t, 10)
            t.buttonStyle = .filled
            t.cardShadow = .strong
            t.imageRadius = 10
            t.navWeight = 600
        },
        make("minimal", "Minimal", "Quiet black and white sans serif with lots of space.") { t in
            t.bodyFont = "ibm-plex-sans"
            t.headingFont = "ibm-plex-sans"
            t.fontSize = 17
            t.h1Size = 34
            t.contentWidth = 40 // 640 px
            t.gutter = 24
            t.light = Palette(background: "#ffffff", surface: "#fafafa", text: "#1a1a1a",
                              muted: "#707070", accent: "#1a1a1a", line: "#ececec")
            t.dark = Palette(background: "#111111", surface: "#181818", text: "#ededed",
                             muted: "#8f8f8f", accent: "#ededed", line: "#262626")
            corners(&t, 2)
            t.cardBorder = true
            t.quoteBarWidth = 2
            t.navSize = 14
        },
        make("garden", "Garden", "Soft and friendly: a rounded serif with a clean sans.") { t in
            t.bodyFont = "work-sans"
            t.headingFont = "fraunces"
            t.fontSize = 18
            t.h1Size = 44
            t.contentWidth = 65 // 1040 px
            t.light = Palette(background: "#f4f6f1", surface: "#ffffff", text: "#22301f",
                              muted: "#5e6b58", accent: "#4c7a3d", line: "#dfe5d8")
            t.dark = Palette(background: "#151a14", surface: "#1d241b", text: "#e4eadf",
                             muted: "#98a590", accent: "#9ccc84", line: "#2c3529")
            corners(&t, 16)
            t.buttonStyle = .filled
            t.buttonPaddingX = 18
            t.cardBorder = false
            t.cardShadow = .soft
            t.imageRadius = 16
            t.quoteColor = .accent
            t.navButton.pill = true
        },
    ]
}
