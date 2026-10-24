import SwiftUI

/// Configuration → Search: turns site search on or off, picks what it can
/// find, and words the field. The Search page (pages/search.md, /search/)
/// shows the field and results; pages can show a search box that opens it.
/// Saved in site.json (`search`).
struct SearchSection: View {
    @Environment(AppModel.self) private var model
    @Binding var config: SiteConfig

    private var search: Binding<SiteConfig.Search> { $config.search }
    private var searchPath: String { "/\(ContentItem.searchSlug)/" }

    /// Pages with a search box line.
    private var boxPages: [ContentItem] {
        (model.site?.items ?? []).filter { !$0.isLinkMenu && PageWidget.search.isUsed(in: $0.body) }
    }

    private var inTopBar: Bool { config.menuLinks.contains { $0.url == searchPath } }

    var body: some View {
        Section {
            Toggle(isOn: search.enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Search this site")
                    Text("Publishes the Search page at \(searchPath), and the list of pages it searches.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
        }

        if config.search.enabled {
            Section {
                ForEach(config.kinds.filter { $0 != .links }, id: \.self) { kind in
                    Toggle(config.pluralName(kind), isOn: Binding(
                        get: { config.search.includes(kind) },
                        set: { on in
                            config.search.kinds.removeAll { $0 == kind.rawValue }
                            if on { config.search.kinds.append(kind.rawValue) }
                        }))
                }
            } header: {
                Text("Find")
            } footer: {
                caption("Drafts are never found on your live site. Home, the 404 page and link menus are left out. A collection's main page is found when its items are.")
            }

            Section("Search Field") {
                TextField("Placeholder", text: search.placeholder, prompt: Text("Search"))
                TextField("Button", text: search.buttonLabel, prompt: Text("Search"))
            }

            Section {
                LabeledContent("Search page") {
                    HStack {
                        Text(searchPath)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        if let page = model.site?.items.first(where: \.isSearchPage) {
                            Button("Open") { model.selection = .item(page.id) }
                        }
                    }
                    .controlSize(.small)
                }
                LabeledContent("Top bar") {
                    if inTopBar {
                        Text("Linked from the top bar")
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Add Search to the Top Bar") { addToTopBar() }
                            .controlSize(.small)
                    }
                }
            } header: {
                Text("Search Page")
            } footer: {
                caption("Link to \(searchPath) from anywhere, such as a menu or the footer. Add ?q= and words to open it with a search done, like \(searchPath)?q=recipes.")
            }

            Section {
                if boxPages.isEmpty {
                    Text("Not in any pages yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(boxPages) { page in
                        LabeledContent(page.title) {
                            Button("Open") { model.selection = .item(page.id) }
                                .controlSize(.small)
                        }
                    }
                }
            } header: {
                Text("Search Boxes in Pages")
            } footer: {
                caption("To put a search box in a page, open the page, click where it should go, and click the magnifying glass in the formatting bar. That adds a <!-- search --> line. Searching from the box opens the Search page with the results.")
            }
        }
    }

    /// Adds a Search link to the top bar's right-hand group, turning it on.
    private func addToTopBar() {
        config.nav.append(.init(title: "Search", url: searchPath))
        config.header.showRightLinks = true
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
