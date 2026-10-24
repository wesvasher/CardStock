import AppKit
import SwiftUI

/// Configuration → Layout: settings for every page (the content container's
/// width, the space at the window's edges, full-width bars), then every page
/// layout in theme/layouts, what it's for, its text areas and which pages
/// use it. Clicking a layout previews a sample page in it.
struct LayoutsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("showConfigPreview") private var showPreview = false

    private var layouts: [PageLayout] { model.site?.layouts ?? [] }
    private var items: [ContentItem] { (model.site?.items ?? []).filter { !$0.isLinkMenu && !$0.isTemplatePage } }

    private var theme: ThemeSettings { model.site?.theme ?? ThemeSettings() }

    private func themeBinding<T>(_ keyPath: WritableKeyPath<ThemeSettings, T>) -> Binding<T> {
        Binding(get: { theme[keyPath: keyPath] },
                set: { value in
                    var updated = theme
                    updated[keyPath: keyPath] = value
                    model.updateTheme(updated)
                })
    }

    var body: some View {
        Form {
            Section {
                ContentWidthPicker(rem: themeBinding(\.contentWidth))
                LabeledContent("Side padding") {
                    NudgeSlider(value: themeBinding(\.gutter), range: 0...64)
                }
                Picker("Top bar and footer", selection: themeBinding(\.fullWidthBars)) {
                    Text("Match Content").tag(false)
                    Text("Full Width").tag(true)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Page")
            } footer: {
                Text("Content width is the most the top bar, page and footer spread across a wide window; narrower windows use their whole width. Side padding is the space kept at the window's edges. Full Width lets the top bar and footer reach the window's edges while the page stays at the content width.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                row(id: "", name: "Standard",
                    description: "Each page type's own design: the title, cover and text in one column. Pages use it until you pick another layout.",
                    areas: [], mainArea: "", types: [],
                    users: items.filter { item in item.layout.isEmpty || !layouts.contains { $0.id == item.layout } })
                ForEach(layouts) { layout in
                    row(id: layout.id, name: layout.name, description: layout.description,
                        areas: layout.areas, mainArea: layout.mainArea, types: layout.types,
                        users: items.filter { $0.layout == layout.id })
                }
            } header: {
                Text("Layouts")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose a page's layout with **Layout** in its editor. In layouts with more than one area, a **section break** (in the formatting bar) moves the text after it to the next area.")
                    Text("Each layout is an HTML file in theme/layouts. Add or change one there, or ask for one, and it shows up here.")
                    Button("Show Layouts Folder in Finder") { showFolder() }
                        .controlSize(.small)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func row(id: String, name: String, description: String, areas: [String], mainArea: String,
                     types: [String], users: [ContentItem]) -> some View {
        let selected = model.previewLayoutID == id
        return Button {
            model.previewLayoutID = id
            if !showPreview { withAnimation(.smooth(duration: 0.35)) { showPreview = true } }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "rectangle.3.group")
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.headline)
                    if !description.isEmpty {
                        Text(description)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if areas.count > 1 {
                        Text("Areas: \(areas.joined(separator: ", ")). Without section breaks, the text goes in \(mainArea).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !types.isEmpty {
                        Text("For \(typeNames(types)).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(users.isEmpty ? "Not used yet"
                         : "Used by \(users.count) \(users.count == 1 ? "page" : "pages")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .help(users.map(\.title).joined(separator: ", "))
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Preview a sample page in this layout")
    }

    /// A layout's `types` words in the site's names: "page, item" → "Static
    /// Pages, Posts, Products".
    private func typeNames(_ words: [String]) -> String {
        let config = model.site?.config ?? SiteConfig()
        var names: [String] = []
        for word in words {
            switch word {
            case "item", "items": names += config.collections.map(\.itemsName)
            case "category", "categories": names.append("categories")
            case "collection", "main": names.append("collection main pages")
            default: names.append(ContentKind(rawValue: word).map(config.pluralName) ?? word)
            }
        }
        return ListFormatter.localizedString(byJoining: names)
    }

    private func showFolder() {
        guard let root = model.site?.root else { return }
        let folder = root.appending(path: PageLayout.folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }
}

/// The content container's width: a menu of common widths, or Custom with a
/// number to type. Stored in rem (16 px each), shown in pixels.
private struct ContentWidthPicker: View {
    @Binding var rem: Double
    @State private var custom = false

    private var px: Int { Int((rem * 16).rounded()) }
    private var isPreset: Bool { ThemeSettings.popularContentWidths.contains { $0.px == px } }

    var body: some View {
        Picker("Content width", selection: Binding(
            get: { custom || !isPreset ? -1 : px },
            set: { choice in
                if choice == -1 {
                    custom = true
                } else {
                    custom = false
                    rem = Double(choice) / 16
                }
            })) {
            ForEach(ThemeSettings.popularContentWidths, id: \.px) { width in
                Text("\(width.px) px — \(width.name)").tag(width.px)
            }
            Divider()
            Text("Custom").tag(-1)
        }
        if custom || !isPreset {
            LabeledContent("Custom width") {
                HStack(spacing: 6) {
                    PixelField(label: "Custom width", value: Binding(
                        get: { px },
                        set: { rem = Double(min(max($0, 320), 3840)) / 16 }), width: 72)
                    Text("px").foregroundStyle(.secondary)
                }
            }
        }
    }
}
