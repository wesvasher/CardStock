import SwiftUI

/// Configuration → Tags: tag pages on or off, then every tag in the site
/// (from pages and site.json) with how many pages have it. Each tag opens
/// to its description and pages, and can be renamed, merged into another
/// tag or deleted from every page. The preview shows the tag's page.
struct TagsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("showConfigPreview") private var showPreview = false
    @State private var query = ""
    @State private var sortByCount = false
    @State private var expanded: Set<String> = []
    @State private var renaming: TagUse?
    @State private var newName = ""
    @State private var deleting: TagUse?
    @State private var adding = false
    @State private var addName = ""

    private var config: SiteConfig { model.site?.config ?? SiteConfig() }
    private var allTags: [TagUse] { model.site?.tagIndex() ?? [] }

    private var shown: [TagUse] {
        let list = allTags.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        guard sortByCount else { return list }
        func uses(_ t: TagUse) -> Int { t.pages.count + t.files.count }
        return list.sorted { uses($0) != uses($1) ? uses($0) > uses($1)
            : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var inTopBar: Bool { config.menuLinks.contains { $0.url == TagSettings.path } }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { config.tags.pages }, set: { on in
                    var updated = config
                    updated.tags.pages = on
                    model.updateConfig(updated)
                })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tag pages")
                        Text("Publishes \(TagSettings.path), listing every tag, and a page for each tag, like \(TagSettings.path("travel")), with its pages and a gallery of its photos. Tags on pages link to them.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                if config.tags.pages {
                    LabeledContent("Top bar") {
                        if inTopBar {
                            Text("Linked from the top bar").foregroundStyle(.secondary)
                        } else {
                            Button("Add Tags to the Top Bar") { addToTopBar() }
                                .controlSize(.small)
                        }
                    }
                }
            } header: {
                Text("Tag Pages")
            }

            Section {
                HStack(spacing: 10) {
                    SearchField(query: $query, prompt: "Find a tag")
                    Picker("Sort", selection: $sortByCount) {
                        Text("A–Z").tag(false)
                        Text("Most Used").tag(true)
                    }
                    .labelsHidden()
                    .fixedSize()
                    Button("New Tag…") { addName = ""; adding = true }
                }
                if allTags.isEmpty {
                    Text("No tags yet. Add tags to a page in its editor, or make one here.")
                        .foregroundStyle(.secondary)
                } else if shown.isEmpty {
                    Text("No tags match “\(query)”.")
                        .foregroundStyle(.secondary)
                }
                ForEach(shown) { tag in
                    DisclosureGroup(isExpanded: Binding(
                        get: { expanded.contains(tag.slug) },
                        set: { open in
                            if open { expanded.insert(tag.slug); preview(tag) } else { expanded.remove(tag.slug) }
                        })) {
                        details(tag)
                    } label: {
                        label(tag)
                    }
                }
            } header: {
                Text(allTags.isEmpty ? "Tags" : "Tags (\(allTags.count))")
            } footer: {
                Text("Tags group anything on your site: pages of every type, and photos and files (tag those on the Files page). A tag spelled differently in different places (“iOS”, “ios”) is one tag. Renaming or deleting a tag changes everything that has it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert("Rename “\(renaming?.name ?? "")”", isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let tag = renaming { model.renameTag(tag.slug, to: newName) }
            }
        } message: {
            Text(renameMessage)
        }
        .confirmationDialog("Delete the “\(deleting?.name ?? "")” tag?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { tag in
            Button("Delete Tag", role: .destructive) { model.deleteTag(tag.slug) }
        } message: { tag in
            Text(tag.isUsed ? "It's taken off \(tag.usage.replacingOccurrences(of: " · ", with: " and ")). They stay." : "Nothing has it.")
        }
        .alert("New Tag", isPresented: $adding) {
            TextField("Name", text: $addName)
            Button("Cancel", role: .cancel) {}
            Button("Add") { addTag() }
        } message: {
            Text("It's ready to pick in any page's or file's Tags. Its page is published once something has it.")
        }
    }

    // MARK: - Rows

    private func label(_ tag: TagUse) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "tag")
                .foregroundStyle(.secondary)
            Text(tag.name)
            Text(tag.usage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer(minLength: 0)
            Menu {
                Button("Rename…") { newName = tag.name; renaming = tag }
                Menu("Merge Into") {
                    ForEach(allTags.filter { $0.slug != tag.slug }) { other in
                        Button(other.name) { model.renameTag(tag.slug, to: other.name) }
                    }
                }
                .disabled(allTags.count < 2)
                Button("Preview Tag Page") { preview(tag, show: true) }
                Divider()
                Button("Delete…", role: .destructive) { deleting = tag }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    @ViewBuilder
    private func details(_ tag: TagUse) -> some View {
        TextField("Description", text: Binding(
            get: { tag.description },
            set: { model.setTagDescription(tag.slug, name: tag.name, description: $0) }),
                  prompt: Text("Shown at the top of the tag's page"), axis: .vertical)
            .lineLimit(1...3)
        ForEach(tag.pages) { page in
            LabeledContent {
                Button("Open") { model.selection = .item(page.id) }
                    .controlSize(.small)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(page.title + (page.isDraft ? " (draft)" : ""))
                    Text("\(config.singularName(page.kind)) · \(page.path)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        ForEach(tag.files, id: \.self) { path in
            LabeledContent {
                Button("Show") { showFile(path) }
                    .controlSize(.small)
            } label: {
                HStack(spacing: 8) {
                    if let file = model.files.first(where: { $0.path == path }) {
                        FileThumbnail(file: file, size: 28)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text((path as NSString).lastPathComponent)
                        Text((path as NSString).deletingLastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Opens the Files page with the file selected.
    private func showFile(_ path: String) {
        model.selectedFileIDs = [path]
        model.selection = .files
    }

    // MARK: - Actions

    private var renameMessage: String {
        guard let tag = renaming else { return "" }
        var text = tag.isUsed ? "It's renamed on \(tag.usage.replacingOccurrences(of: " · ", with: " and ")). " : ""
        text += "Renaming it to another tag's name merges the two."
        return text
    }

    /// Shows the tag's page in the preview (opening the preview if asked).
    private func preview(_ tag: TagUse, show: Bool = false) {
        model.previewTagSlug = tag.slug
        if show && !showPreview { withAnimation(.smooth(duration: 0.35)) { showPreview = true } }
    }

    private func addTag() {
        let name = addName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !allTags.contains(where: { $0.slug == TagSettings.slug(name) }) else { return }
        var updated = config
        updated.tags.list.append(.init(name: name))
        model.updateConfig(updated)
    }

    private func addToTopBar() {
        var updated = config
        updated.nav.append(.init(title: "Tags", url: TagSettings.path))
        updated.header.showRightLinks = true
        model.updateConfig(updated)
    }
}
