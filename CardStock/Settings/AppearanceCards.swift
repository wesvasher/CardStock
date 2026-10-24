import SwiftUI

/// Light, Dark and Auto tiles for choosing a site's appearance.
struct AppearanceCards: View {
    @Binding var selection: ThemeSettings.Appearance
    /// Hover text for each tile, when the defaults (about site visitors)
    /// don't fit, as in the app's own Settings.
    var helpText: [ThemeSettings.Appearance: String] = [:]

    var body: some View {
        ChoiceCards(selection: $selection, options: ThemeSettings.Appearance.allCases.map { option in
            switch option {
            case .light:
                .init(value: option, title: "Light", systemImage: "sun.max.fill",
                      help: helpText[option] ?? "Always use the light colors")
            case .dark:
                .init(value: option, title: "Dark", systemImage: "moon.fill",
                      help: helpText[option] ?? "Always use the dark colors")
            case .auto:
                .init(value: option, title: "Auto", systemImage: "circle.lefthalf.filled",
                      help: helpText[option] ?? "Match each visitor's device")
            }
        })
    }
}
