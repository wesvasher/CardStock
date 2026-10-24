import AppKit
import SwiftUI

/// Configuration → Layouts: every page layout in theme/layouts, what it's
/// for, its text areas and which pages use it. Clicking one previews a
/// sample page in it.
struct LayoutsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("showConfigPreview") private var showPreview = false

    private var layouts: [PageLayout] { model.site?.layouts ?? [] }
    private var items: [ContentItem] { (model.site?.items ?? []).filter { !$0.isLinkMenu && !$0.isTemplatePage } }

    var body: some View {
        Form {
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
                     types: [ContentKind], users: [ContentItem]) -> some View {
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
                        Text("For \(types.map(\.pluralName).joined(separator: ", ")).")
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

    private func showFolder() {
        guard let root = model.site?.root else { return }
        let folder = root.appending(path: PageLayout.folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }
}
