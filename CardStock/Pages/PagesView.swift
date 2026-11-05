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
    /// The folder New Page puts the page in, from when it was clicked.
    @State private var newPageFolder = PageFolders.top
    /// The folder being named: a new one (inside `parent`) or a rename.
    @State private var naming: FolderNaming?
    @State private var folderName = ""
    @State private var pendingFolderRemove: String?
    /// Pages selected in the list (⌘- and ⇧-click select more). The editor
    /// shows one of them, `model.selectedPageID`: the one last clicked.
    @State private var selectedIDs: Set<URL> = []

    private enum FolderNaming: Equatable {
        case new(parent: String)
        case rename(String)
    }

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

    /// Without a search or filter, pages are shown in their folders.
    private var isBrowsing: Bool { !isFiltered }

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
                List(selection: $selectedIDs) {
                    if isBrowsing {
                        contents(of: PageFolders.top, pages: shown)
                    } else {
                        ForEach(shown) { pageRow($0) }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                // Dropped on empty space below the rows: back to the top.
                .dropDestination(for: String.self) { items, _ in _ = drop(items, into: PageFolders.top) }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .sheet(isPresented: $showNewPage) { NewItemSheet(kind: .page, folder: newPageFolder) }
        .onAppear {
            // Start with a page selected so the preview shows something.
            if model.selectedPage == nil { model.selectedPageID = shown.first?.id }
            selectedIDs = model.selectedPageID.map { [$0] } ?? []
            revealSelectedPage()
        }
        .onChange(of: selectedIDs) { old, new in
            // The page just clicked goes in the editor; otherwise keep the
            // one shown while it's still selected. Selecting only folders
            // leaves the editor as it is.
            let pages = new.filter { Self.folderPath($0) == nil }
            guard !pages.isEmpty || new.isEmpty else { return }
            let added = pages.subtracting(old)
            if added.count == 1 {
                model.selectedPageID = added.first
            } else if let current = model.selectedPageID, pages.contains(current) {
                return
            } else {
                model.selectedPageID = shown.first { pages.contains($0.id) }?.id
            }
        }
        .onChange(of: model.selectedPageID) {
            // Opened from elsewhere in the app: select just that page.
            if let id = model.selectedPageID, !selectedIDs.contains(id) { selectedIDs = [id] }
            revealSelectedPage()
        }
        .alert(isRenaming ? "Rename Folder" : "New Folder",
               isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Name", text: $folderName)
            Button("Cancel", role: .cancel) { naming = nil }
            Button(isRenaming ? "Rename" : "Create") { finishNaming() }
                .disabled(PageFolders.name(for: folderName) == nil)
        } message: {
            Text("Folders only organize this list. Pages keep their addresses.")
        }
        .confirmationDialog("Remove “\(pendingFolderRemove.map(PageFolders.name(of:)) ?? "")”?",
                            isPresented: Binding(get: { pendingFolderRemove != nil },
                                                 set: { if !$0 { pendingFolderRemove = nil } })) {
            Button("Remove Folder") {
                if let path = pendingFolderRemove { model.removePageFolder(path) }
                pendingFolderRemove = nil
            }
        } message: {
            Text(removeMessage)
        }
    }

    // MARK: - Folders

    private var isRenaming: Bool {
        if case .rename = naming { return true }
        return false
    }

    private func startNewFolder(in parent: String) {
        folderName = ""
        naming = .new(parent: parent)
    }

    private func finishNaming() {
        switch naming {
        case .new(let parent):
            if model.newPageFolder(folderName, in: parent) != nil {
                // Show the new folder where it was made.
                model.expandedPageFolders.formUnion(PageFolders.ancestors(of: parent))
            }
        case .rename(let path):
            model.renamePageFolder(path, to: folderName)
        case nil:
            break
        }
        naming = nil
    }

    private var removeMessage: String {
        guard let path = pendingFolderRemove else { return "" }
        let count = pages.filter { PageFolders.isInside($0.folder, path) && !$0.folder.isEmpty }.count
        let place = PageFolders.parent(of: path).isEmpty ? "the top of the list" : PageFolders.name(of: PageFolders.parent(of: path))
        guard count > 0 else { return "It's empty." }
        return "The \(count) \(count == 1 ? "page" : "pages") in it move to \(place). No pages are deleted."
    }

    /// Opens the folders holding the selected page, so it's in view.
    private func revealSelectedPage() {
        guard let page = model.selectedPage, !page.folder.isEmpty else { return }
        model.expandedPageFolders.formUnion(PageFolders.ancestors(of: page.folder))
    }

    private func isExpanded(_ path: String) -> Binding<Bool> {
        Binding(get: { model.expandedPageFolders.contains(path) },
                set: { open in
                    if open { model.expandedPageFolders.insert(path) } else { model.expandedPageFolders.remove(path) }
                })
    }

    private func toggle(_ path: String) {
        withAnimation(.snappy(duration: 0.2)) {
            if model.expandedPageFolders.contains(path) {
                model.expandedPageFolders.remove(path)
            } else {
                model.expandedPageFolders.insert(path)
            }
        }
    }

    /// The folders inside `parent`, each opening to show its own contents,
    /// then its pages, in the chosen order. (AnyView, since it contains itself.)
    private func contents(of parent: String, pages: [ContentItem]) -> AnyView {
        let folders = PageFolders.children(of: parent, in: model.pageFolders)
        return AnyView(Group {
            ForEach(folders, id: \.self) { path in
                DisclosureGroup(isExpanded: isExpanded(path)) {
                    contents(of: path, pages: pages)
                } label: {
                    FolderDropTarget(isOpen: model.expandedPageFolders.contains(path)) {
                        folderRow(path, pages: pages)
                    } onDrop: { items in
                        drop(items, into: path)
                    } onHover: {
                        withAnimation(.snappy(duration: 0.2)) { _ = model.expandedPageFolders.insert(path) }
                    }
                    .tag(Self.folderID(path))
                    .draggable(Self.dragPrefix + Self.folderLine + path)
                    .contextMenu { folderMenu(path) }
                }
            }
            ForEach(pages.filter { $0.folder == parent }) { pageRow($0) }
        })
    }

    private func folderRow(_ path: String, pages: [ContentItem]) -> some View {
        let count = pages.filter { !$0.folder.isEmpty && PageFolders.isInside($0.folder, path) }.count
        return Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(PageFolders.name(of: path)).lineLimit(1)
                Text(count == 0 ? "Empty" : "\(count) \(count == 1 ? "page" : "pages")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } icon: {
            Image(systemName: "folder.fill").foregroundStyle(.tint)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // Simultaneous, so a single click still selects the row.
        .simultaneousGesture(TapGesture(count: 2).onEnded { toggle(path) })
        .help("Click the triangle or double-click to show the pages inside. Drop pages here to move them in.")
    }

    @ViewBuilder
    private func folderMenu(_ path: String) -> some View {
        Button(model.expandedPageFolders.contains(path) ? "Collapse" : "Expand") { toggle(path) }
        Button("New Folder Inside…") { startNewFolder(in: path) }
        Button("Rename…") {
            folderName = PageFolders.name(of: path)
            naming = .rename(path)
        }
        moveMenu(excluding: { $0 == PageFolders.parent(of: path) || (!$0.isEmpty && PageFolders.isInside($0, path)) }) {
            model.movePageFolder(path, into: $0)
        }
        Divider()
        Button("Remove Folder…") { pendingFolderRemove = path }
    }

    /// Every folder, indented by depth, for Move To menus.
    private func moveMenu(title: String = "Move To", excluding: @escaping (String) -> Bool,
                          move: @escaping (String) -> Void) -> some View {
        Menu(title) {
            Button("Pages (top level)") { move(PageFolders.top) }
                .disabled(excluding(PageFolders.top))
            if !model.pageFolders.isEmpty { Divider() }
            ForEach(model.pageFolders, id: \.self) { path in
                let depth = path.split(separator: "/").count - 1
                Button(String(repeating: "    ", count: depth) + PageFolders.name(of: path)) { move(path) }
                    .disabled(excluding(path))
            }
            Divider()
            Button("New Folder…") { startNewFolder(in: PageFolders.top) }
        }
    }

    /// List ids for folder rows: not file URLs, so they never match a page.
    private static func folderID(_ path: String) -> URL {
        URL(string: "cardstock-page-folder:" + (path.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? path))!
    }

    private static func folderPath(_ id: URL) -> String? {
        guard id.scheme == "cardstock-page-folder" else { return nil }
        return String(id.absoluteString.dropFirst("cardstock-page-folder:".count)).removingPercentEncoding
    }

    /// Where New Page and New Folder put things: the folder selected, when
    /// just one is; otherwise the top of the list.
    private var targetFolder: String {
        let folders = selectedIDs.compactMap(Self.folderPath)
        return folders.count == 1 && model.pageFolders.contains(folders[0]) ? folders[0] : PageFolders.top
    }

    /// Pages and folders being dragged: `cardstock-pages:`, then a line
    /// per page (its file path) or folder (`folder:` and its path).
    private static let dragPrefix = "cardstock-pages:"
    private static let folderLine = "folder:"

    /// Moves dropped pages and folders into `destination`.
    private func drop(_ payloads: [String], into destination: String) -> Bool {
        let lines = payloads.flatMap { text -> [String] in
            guard text.hasPrefix(Self.dragPrefix) else { return [] }
            return text.dropFirst(Self.dragPrefix.count).split(separator: "\n").map(String.init)
        }
        guard !lines.isEmpty else { return false }
        for line in lines where line.hasPrefix(Self.folderLine) {
            let path = String(line.dropFirst(Self.folderLine.count))
            if path != destination && PageFolders.parent(of: path) != destination
                && (destination.isEmpty || !PageFolders.isInside(destination, path)) {
                model.movePageFolder(path, into: destination)
            }
        }
        let ids = lines.filter { !$0.hasPrefix(Self.folderLine) }.map { URL(filePath: $0) }
        if !ids.isEmpty { model.movePages(ids, to: destination) }
        return true
    }

    /// The page, or every selected page when it's one of them.
    private func pagesActedOn(_ page: ContentItem) -> [ContentItem] {
        guard selectedIDs.contains(page.id), selectedIDs.count > 1 else { return [page] }
        return shown.filter { selectedIDs.contains($0.id) }
    }

    private func pageRow(_ page: ContentItem) -> some View {
        let group = pagesActedOn(page)
        return row(page)
            .tag(page.id)
            .draggable(Self.dragPrefix + group.map(\.fileURL.path).joined(separator: "\n")) {
                Label(group.count == 1 ? page.title : "\(group.count) pages", systemImage: group.count == 1 ? "doc" : "doc.on.doc")
                    .padding(6)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            .contextMenu {
                moveMenu(title: group.count == 1 ? "Move To" : "Move \(group.count) Pages To",
                         excluding: { folder in group.allSatisfy { $0.folder == folder } }) {
                    model.movePages(group.map(\.id), to: $0)
                }
                Divider()
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(group.map(\.fileURL)) }
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
        if selectedIDs.count > 1 { text += " · \(selectedIDs.count) selected" }
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
            Button {
                newPageFolder = targetFolder
                showNewPage = true
            } label: {
                Label("New Page…", systemImage: "plus")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
            .help(targetFolder.isEmpty ? "Make a new page" : "Make a new page in \(PageFolders.name(of: targetFolder))")
            Button { startNewFolder(in: targetFolder) } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .roundGlass(30)
            .help(targetFolder.isEmpty ? "New Folder: group pages in this list. Their addresses don't change."
                  : "New Folder inside \(PageFolders.name(of: targetFolder))")
            .accessibilityLabel("New Folder")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: - Rows

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
        if !isBrowsing && !page.folder.isEmpty { parts.append("In \(PageFolders.name(of: page.folder))") }
        if menuURLs.contains(page.path) { parts.append("In Menu") }
        // Short addresses from Configuration → Folders.
        for folder in config.folders where folder.page == page.slug { parts.append("Also \(folder.path)") }
        return parts.joined(separator: " · ")
    }

    private func clear() {
        filter = .all
        query = ""
    }
}
