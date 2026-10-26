import AppKit
import SwiftUI

/// The website's high-level details: title, description, address, language
/// and icon. Configuration → Site Details.
struct SiteDetailsView: View {
    @Environment(AppModel.self) private var model
    let site: Site

    var body: some View {
        Form {
            Section("Site") {
                TextField("Title", text: config(\.title))
                TextField("Description", text: config(\.description), axis: .vertical)
                    .lineLimit(1...4)
                TextField("Author", text: config(\.author))
                TextField("Web address", text: config(\.url), prompt: Text("https://example.pages.dev"))
                TextField("Language", text: config(\.language), prompt: Text("en"))
            }

            SiteIconSection()
        }
        .formStyle(.grouped)
    }

    private func config<T>(_ keyPath: WritableKeyPath<SiteConfig, T>) -> Binding<T> {
        Binding(
            get: { (model.site?.config ?? site.config)[keyPath: keyPath] },
            set: { newValue in
                guard var config = model.site?.config else { return }
                config[keyPath: keyPath] = newValue
                model.updateConfig(config)
            })
    }
}
