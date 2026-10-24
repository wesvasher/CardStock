import AppKit
import SwiftUI

/// The narrow list of the site's pages on the left of the Pages view, with
/// search and a show and sort menu. Clicking a page opens it in the editor
/// next to it.
struct PagesView: View {
    @Environment(AppModel.self) private var model
    let site: Site

    @State private var query = ""
    @State private var filter = PageFilter.all
    @State private var sort = PageSort.type
    @State private var showNewPage = false

    enum PageFilter: Hashable {
        case all
        case type(ContentKind)
        /// A collection's main page, items and categories.
        case collection(String)
        case published
        case drafts
        case inMenu

        func title(_ config: SiteConfig) -> String {
            switch self {
            case .all: "All Pages"
            case .type(let kind): config.pluralName(kind)
            case .collection(let id): config.collection(id)?.name ?? id
            case .published: "Published"
            case .drafts: "Drafts"
            case .inMenu: "In Menu"
            }
        }
    }

    enum PageSort: String, CaseIterable {
        case type = "Type"
        case title = "Title"
        case address = "Address"
        case recent = "Recently Edited"
    }

    private var config: SiteConfig { (model.site ?? site).config }

    /// Kinds in list order: static pages, each collection (main page,
    /// items, categories), link menus.
    private var kindOrder: [ContentKind] {
        [.page] + config.collections.flatMap { [$0.mainKind, $0.itemKind, $0.categoryKind] } + [.links]
    }

    private func orderIndex(_ kind: ContentKind) -> Int {
        kindOrder.firstIndex(of: kind) ?? kindOrder.count
    }

    /// Every page, Home first, then by type.
    private var pages: [ContentItem] {
        let current = model.site ?? site
        return current.items.enumerated().sorted { a, b in
            if a.element.isHome != b.element.isHome { return a.element.isHome }
            let (x, y) = (orderIndex(a.element.kind), orderIndex(b.element.kind))
            return x != y ? x < y : a.offset < b.offset
        }.map(\.element)
    }

    private var menuURLs: Set<String> { Set((model.site ?? site).config.menuLinks.map(\.url)) }

    private var shown: [ContentItem] {
        let menu = menuURLs
        return pages
            .filter { page in
                switch filter {
                case .all: true
                case .published: !page.isDraft && !page.isTemplatePage
                case .drafts: page.isDraft
                case .inMenu: menu.contains(page.path)
                case .type(let kind): page.kind == kind
                case .collection(let id): page.kind.collectionID == id
                }
            }
            .filter { page in
                query.isEmpty || page.title.localizedCaseInsensitiveContains(query)
                    || page.path.localizedCaseInsensitiveContains(query)
                    || page.body.localizedCaseInsensitiveContains(query)
            }
            .sorted { a, b in
                // Home always comes first.
                if a.isHome != b.isHome { return a.isHome }
                switch sort {
                case .title: return a.title.localizedStandardCompare(b.title) == .orderedAscending
                case .type:
                    let (x, y) = (orderIndex(a.kind), orderIndex(b.kind))
                    if x != y { return x < y }
                    // Posts newest first, everything else by title.
                    if a.date != b.date { return a.date > b.date }
                    return a.title.localizedStandardCompare(b.title) == .orderedAscending
                case .address: return a.path < b.path
                case .recent: return Self.modified(a) > Self.modified(b)
                }
            }
    }

    private static func modified(_ item: ContentItem) -> Date {
        (try? item.fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private var isFiltered: Bool { filter != .all || !query.isEmpty }

    private var clearTitle: String {
        switch (filter != .all, !query.isEmpty) {
        case (true, true): "Clear Filters and Search"
        case (true, false): "Clear Filters"
        default: "Clear Search"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if shown.isEmpty {
                ContentUnavailableView {
                    Label("No Matching Pages", systemImage: "magnifyingglass")
                } description: {
                    Text("No pages match your search and filters.")
                } actions: {
                    Button(clearTitle) { clear() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(shown, selection: pageSelection) { page in
                    row(page)
                        .tag(page.id)
                        .contextMenu {
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([page.fileURL]) }
                        }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .sheet(isPresented: $showNewPage) { NewItemSheet(kind: .page) }
        .onAppear {
            // Start with a page selected so the preview shows something.
            if model.selectedPage == nil { model.selectedPageID = shown.first?.id }
        }
    }

    // MARK: - Header and footer

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SearchField(query: $query, prompt: "Search pages")
                filterMenu
            }
            HStack(spacing: 10) {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if isFiltered {
                    Button(clearTitle) { withAnimation(.snappy) { clear() } }
                        .buttonStyle(.link)
                        .font(.caption.weight(.medium))
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var summary: String {
        let count = shown.count
        var text = "\(count) \(count == 1 ? "page" : "pages")"
        if isFiltered { text += " (of \(pages.count))" }
        let drafts = shown.filter(\.isDraft).count
        if drafts > 0 && filter != .drafts { text += " · \(drafts) \(drafts == 1 ? "draft" : "drafts")" }
        return text
    }

    private var filterMenu: some View {
        Menu {
            Section("Show") {
                Picker("Show", selection: $filter) {
                    Text(PageFilter.all.title(config)).tag(PageFilter.all)
                    Text("Static Pages").tag(PageFilter.type(.page))
                    ForEach(config.collections) { c in
                        Text(c.name).tag(PageFilter.collection(c.id))
                    }
                    Text("Link Menus").tag(PageFilter.type(.links))
                    Divider()
                    ForEach([PageFilter.published, .drafts, .inMenu], id: \.self) { Text($0.title(config)).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section("Sort By") {
                Picker("Sort By", selection: $sort) {
                    ForEach(PageSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(filter == .all ? Color.primary : Color.accentColor)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .roundGlass(30)
        .help("Showing \(filter.title(config)) · \(sort.rawValue)")
    }

    private var footer: some View {
        HStack {
            Button { showNewPage = true } label: {
                Label("New Page…", systemImage: "plus")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: - Rows

    private var pageSelection: Binding<URL?> {
        Binding(get: { model.selectedPageID }, set: { model.selectedPageID = $0 })
    }

    /// A standard list row: icon, title, and the address with its state.
    private func row(_ page: ContentItem) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(page.title)
                    .lineLimit(1)
                Text(details(page))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: page.isHome ? "house" : page.isNotFoundPage ? "exclamationmark.triangle"
                  : page.isTemplatePage ? "swatchpalette" : page.isSearchPage ? "magnifyingglass" : config.systemImage(page.kind))
        }
        .padding(.vertical, 2)
    }

    private func details(_ page: ContentItem) -> String {
        if page.isLinkMenu {
            let count = LinkMenu.links(in: page.body).count
            return "Link Menu · \(count) \(count == 1 ? "link" : "links")"
        }
        if page.isTemplatePage { return "Template · Preview only" }
        if page.isSearchPage {
            return (model.site ?? site).config.search.enabled ? "Search · \(page.path)" : "Search · Off"
        }
        var parts = [page.isHome ? "Home" : page.isNotFoundPage ? "Broken links" : config.singularName(page.kind), page.path]
        if let layout = model.site?.layouts.first(where: { $0.id == page.layout }) { parts.append(layout.name) }
        if page.isDraft && !page.isHome { parts.append("Draft") }
        if menuURLs.contains(page.path) { parts.append("In Menu") }
        return parts.joined(separator: " · ")
    }

    private func clear() {
        filter = .all
        query = ""
    }
}
