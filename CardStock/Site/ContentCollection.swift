import Foundation

/// A collection: a section of the site made of a main page that lists
/// items, the items themselves, and (optionally) category pages that list
/// some of them. A blog (posts), a shop (products), a portfolio (projects)
/// or videos. Saved in site.json (`collections`), edited in
/// Configuration → Collections.
///
/// The `id` is also the address: the main page is `/<id>/`, and every
/// other page in the collection (items and categories) is
/// `/<id>/pages/<slug>/`. Pages say which collection they're in with `type:`
/// front matter: the item type (`post` for the blog, `product` for the
/// shop, else the id) or the category type (`<id>-category`). The main
/// page is `pages/<id>.md` with `type: collection`.
struct ContentCollection: Codable, Equatable, Sendable, Identifiable {
    /// A starting point for a new collection's names and settings.
    enum Preset: String, Codable, CaseIterable, Sendable, Identifiable {
        case blog, shop, portfolio, videos, custom
        var id: Self { self }

        var title: String {
            switch self {
            case .blog: "Blog"
            case .shop: "Shop"
            case .portfolio: "Portfolio"
            case .videos: "Videos"
            case .custom: "Custom"
            }
        }

        var systemImage: String {
            switch self {
            case .blog: "square.and.pencil"
            case .shop: "bag"
            case .portfolio: "photo.on.rectangle.angled"
            case .videos: "play.rectangle"
            case .custom: "square.stack"
            }
        }

        var summary: String {
            switch self {
            case .blog: "Dated posts, newest first, in the RSS feed and on Home."
            case .shop: "Products with a price and a Buy button, shown as cards."
            case .portfolio: "Projects or artwork shown as an image gallery."
            case .videos: "Pages built around a YouTube, Vimeo or video file."
            case .custom: "Your own kind of page, like recipes, events or episodes."
            }
        }
    }

    /// How the main page and category pages list the items.
    enum ListStyle: String, Codable, CaseIterable, Sendable {
        /// Rows: title, date and summary.
        case list
        /// Cards in a grid: image, title, price and summary.
        case cards
        /// Images in a grid, with the title under each.
        case gallery
    }

    enum Sort: String, Codable, CaseIterable, Sendable {
        case newest, oldest, title

        var title: String {
            switch self {
            case .newest: "Newest First"
            case .oldest: "Oldest First"
            case .title: "By Title"
            }
        }
    }

    static let blogID = "blog"
    static let shopID = "shop"

    /// The address folder and what `type:` is built from. Can't change.
    var id: String
    var preset: Preset
    /// The collection's name, e.g. "Blog".
    var name: String
    /// One item, e.g. "Post".
    var itemName: String
    /// More than one, e.g. "Posts".
    var itemsName: String
    /// An SF Symbol for the app's lists.
    var icon: String

    // MARK: Main page and category pages
    var listStyle: ListStyle
    /// Cards or gallery images per row on wide screens.
    var columns: Int
    var sort: Sort
    var listImages: Bool
    var listDates: Bool
    var listSummaries: Bool
    /// Links to the categories above the list.
    var listCategories: Bool
    /// Shown when there's nothing to list. Empty uses "No <items> yet."
    var emptyText: String

    // MARK: Item pages
    /// Items have a date (the editor shows a Date field; sorting by date uses it).
    var dated: Bool
    var showDate: Bool
    var showCover: Bool
    var showTags: Bool
    var showCategories: Bool
    /// A price and a Buy button that goes to a checkout link.
    var selling: Bool
    /// A video link, shown as a player at the top of the page.
    var video: Bool
    /// Links to the previous and next item and back to the main page.
    var prevNext: Bool
    /// The layout new items start with (a theme/layouts id), empty for Standard.
    var itemLayout: String

    // MARK: Elsewhere
    /// Category pages (`<id>-category`) that list some of the items.
    var categories: Bool
    /// Listed on the Home page (with the other collections that are).
    var onHome: Bool
    /// In the RSS feed (feed.xml).
    var inFeed: Bool

    init(preset: Preset, id: String, name: String? = nil) {
        self.id = id
        self.preset = preset
        icon = preset.systemImage
        listStyle = .cards
        columns = 3
        sort = .newest
        listImages = true
        listDates = false
        listSummaries = true
        listCategories = false
        emptyText = ""
        dated = false
        showDate = false
        showCover = true
        showTags = true
        showCategories = true
        selling = false
        video = false
        prevNext = false
        itemLayout = ""
        categories = true
        onHome = false
        inFeed = false
        switch preset {
        case .blog:
            (self.name, itemName, itemsName) = ("Blog", "Post", "Posts")
            listStyle = .list
            listImages = false
            listDates = true
            dated = true
            showDate = true
            prevNext = true
            onHome = true
            inFeed = true
        case .shop:
            (self.name, itemName, itemsName) = ("Shop", "Product", "Products")
            sort = .title
            selling = true
            showTags = false
        case .portfolio:
            (self.name, itemName, itemsName) = ("Portfolio", "Project", "Projects")
            listStyle = .gallery
            listSummaries = false
            dated = true
            prevNext = true
        case .videos:
            (self.name, itemName, itemsName) = ("Videos", "Video", "Videos")
            dated = true
            showDate = true
            video = true
            showCover = false
            prevNext = true
        case .custom:
            (self.name, itemName, itemsName) = ("Collection", "Item", "Items")
        }
        if let name, !name.isEmpty { self.name = name }
    }

    private enum CodingKeys: String, CodingKey {
        case id, preset, name, itemName, itemsName, icon, listStyle, columns, sort, listImages, listDates,
             listSummaries, listCategories, emptyText, dated, showDate, showCover, showTags, showCategories,
             selling, video, prevNext, itemLayout, categories, onHome, inFeed
    }

    /// Missing settings come from the preset, so older or hand-written
    /// entries keep working.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decodeIfPresent(String.self, forKey: .id) ?? "collection"
        let preset = (try? c.decodeIfPresent(Preset.self, forKey: .preset))
            ?? (id == Self.blogID ? .blog : id == Self.shopID ? .shop : .custom)
        self.init(preset: preset, id: id)
        func read<T: Decodable>(_ key: CodingKeys, _ value: inout T) {
            if let v = try? c.decodeIfPresent(T.self, forKey: key) { value = v }
        }
        read(.name, &name)
        read(.itemName, &itemName)
        read(.itemsName, &itemsName)
        read(.icon, &icon)
        read(.listStyle, &listStyle)
        read(.columns, &columns)
        read(.sort, &sort)
        read(.listImages, &listImages)
        read(.listDates, &listDates)
        read(.listSummaries, &listSummaries)
        read(.listCategories, &listCategories)
        read(.emptyText, &emptyText)
        read(.dated, &dated)
        read(.showDate, &showDate)
        read(.showCover, &showCover)
        read(.showTags, &showTags)
        read(.showCategories, &showCategories)
        read(.selling, &selling)
        read(.video, &video)
        read(.prevNext, &prevNext)
        read(.itemLayout, &itemLayout)
        read(.categories, &categories)
        read(.onHome, &onHome)
        read(.inFeed, &inFeed)
    }

    // MARK: - Types and addresses

    /// The `type:` value of this collection's items.
    static func itemType(_ id: String) -> String {
        switch id {
        case blogID: "post"
        case shopID: "product"
        default: id
        }
    }

    static func categoryType(_ id: String) -> String { id + "-category" }

    var itemType: String { Self.itemType(id) }
    var categoryType: String { Self.categoryType(id) }
    var mainPath: String { "/\(id)/" }
    var itemKind: ContentKind { .item(id) }
    var categoryKind: ContentKind { .category(id) }
    var mainKind: ContentKind { .main(id) }

    var categoryName: String { "\(name) Category" }
    var shownEmptyText: String {
        let t = emptyText.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "No \(itemsName.lowercased()) yet." : t
    }

    /// A collection for pages whose `type:` names one that isn't in site.json.
    static func fallback(_ id: String) -> ContentCollection {
        switch id {
        case blogID: ContentCollection(preset: .blog, id: id)
        case shopID: ContentCollection(preset: .shop, id: id)
        default:
            ContentCollection(preset: .custom, id: id,
                              name: id.replacingOccurrences(of: "-", with: " ").capitalized)
        }
    }

    /// Words that can't be a collection's id, because they're other page
    /// types or addresses the site already uses.
    static let reservedIDs: Set<String> = [
        "page", "pages", "links", "post", "posts", "product", "collection", "category", "media", "assets",
        "theme", "static", "public", "tags", "tag", "search", "index", "404", "template", "feed", "feed-xml",
    ]

    /// Why `id` can't be a new collection's id in `site`, or nil when it can.
    static func problem(withID id: String, in site: Site) -> String? {
        if id.isEmpty { return "Type an address." }
        if id != Site.slugify(id) { return "Use lowercase letters, numbers and hyphens." }
        if reservedIDs.contains(id) || id.hasSuffix("-category") || id.hasPrefix("_") {
            return "“\(id)” is used by CardStock. Choose another address."
        }
        if site.config.collections.contains(where: { $0.id == id }) {
            return "Another collection uses /\(id)/."
        }
        if site.config.folders.contains(where: { $0.name == id }) {
            return "/\(id)/ is one of your folders (Configuration → Folders)."
        }
        if let page = site.items.first(where: { $0.slug == id }) {
            return "The page “\(page.title)” is already named \(id)."
        }
        return nil
    }

    /// Suggested symbols for the icon menu.
    static let iconChoices = [
        "square.and.pencil", "newspaper", "bag", "cart", "photo.on.rectangle.angled", "paintbrush", "camera",
        "play.rectangle", "film", "music.note", "mic", "book", "fork.knife", "calendar", "map", "airplane",
        "briefcase", "hammer", "graduationcap", "lightbulb", "star", "heart", "square.stack", "folder",
    ]

    /// Collections sorted by name.
    static func alphabetical(_ list: [ContentCollection]) -> [ContentCollection] {
        list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Collections for a site whose site.json has none yet: the blog, and
    /// the shop when the site has products or shop categories.
    static func defaults(for items: [ContentItem]) -> [ContentCollection] {
        var list = [ContentCollection(preset: .blog, id: blogID)]
        if items.contains(where: { $0.kind == .product || $0.kind == .shopCategory }) {
            list.append(ContentCollection(preset: .shop, id: shopID))
        }
        return list
    }
}

/// What a page is. Every page lives in `pages/`; its `type:` front matter
/// says which kind it is (no `type` means a static page).
enum ContentKind: Hashable, Sendable, Identifiable {
    /// A page on its own.
    case page
    /// A collection's main page, listing its items: `pages/<id>.md` with
    /// `type: collection`.
    case main(String)
    /// An item in a collection, such as a blog post or a product.
    case item(String)
    /// A category page in a collection, listing the items put in it.
    case category(String)
    /// A list of links for a footer drop-down menu; not published.
    case links

    static let post = ContentKind.item(ContentCollection.blogID)
    static let product = ContentKind.item(ContentCollection.shopID)
    static let blogCategory = ContentKind.category(ContentCollection.blogID)
    static let shopCategory = ContentKind.category(ContentCollection.shopID)

    /// `type:` of a collection's main page.
    static let mainType = "collection"

    var id: String {
        switch self {
        case .page: "page"
        case .links: "links"
        case .main(let c): "main:" + c
        case .item(let c): "item:" + c
        case .category(let c): "category:" + c
        }
    }

    /// The `type:` front matter value.
    var rawValue: String {
        switch self {
        case .page: "page"
        case .links: "links"
        case .main: Self.mainType
        case .item(let c): ContentCollection.itemType(c)
        case .category(let c): ContentCollection.categoryType(c)
        }
    }

    /// Reads a `type:` value. A main page's collection is its file name
    /// (`slug`); without one, `collection` isn't understood.
    init?(rawValue: String, slug: String? = nil) {
        let raw = rawValue.trimmingCharacters(in: .whitespaces).lowercased()
        switch raw {
        case "", "page": self = .page
        case "links": self = .links
        case "post": self = .post
        case "product": self = .product
        case Self.mainType:
            guard let slug else { return nil }
            self = .main(slug)
        default:
            guard raw == Site.slugify(raw) else { return nil }
            if raw.hasSuffix("-category") {
                let id = String(raw.dropLast("-category".count))
                guard !id.isEmpty else { return nil }
                self = .category(id)
            } else {
                self = .item(raw)
            }
        }
    }

    /// The collection this kind of page belongs to.
    var collectionID: String? {
        switch self {
        case .main(let c), .item(let c), .category(let c): c
        case .page, .links: nil
        }
    }

    var isItem: Bool { if case .item = self { true } else { false } }
    var isCategory: Bool { if case .category = self { true } else { false } }
    var isMain: Bool { if case .main = self { true } else { false } }

    /// Every page's file is in this folder.
    static let folder = "pages"
    var folder: String { Self.folder }

    /// Where images added in the editor go, inside media/.
    var mediaFolder: String { self == .post ? "posts" : "pages" }

    /// The folder pages that aren't in a collection are published in.
    static let pagesFolder = "pages"

    /// Published path for a page of this type with this slug. Only
    /// collections have addresses of their own (`/<id>/`); their items and
    /// categories are in `/<id>/pages/`, and every other page in `/pages/`.
    /// Home is the site's own address.
    func path(for slug: String) -> String {
        switch self {
        case .page:
            switch slug {
            case ContentItem.homeSlug: "/"
            case ContentItem.notFoundSlug: "/404.html"
            case ContentItem.templateSlug: SiteRenderer.templatePagePath
            default: "/\(Self.pagesFolder)/\(slug)/"
            }
        case .main(let c): "/\(c)/"
        case .item(let c), .category(let c): "/\(c)/\(Self.pagesFolder)/\(slug)/"
        // Only shown in the preview; never published.
        case .links: "/links/\(slug)/"
        }
    }

    /// Where a page was published before version 0.6: static pages at
    /// `/<slug>/`, blog posts at `/posts/<slug>/`, and other items and
    /// categories at `/<id>/<slug>/`. Used to redirect and update old links.
    func legacyPath(for slug: String) -> String {
        switch self {
        case .page where ![ContentItem.homeSlug, ContentItem.notFoundSlug, ContentItem.templateSlug].contains(slug):
            "/\(slug)/"
        case .item(let c) where c == ContentCollection.blogID: "/posts/\(slug)/"
        case .item(let c), .category(let c): "/\(c)/\(slug)/"
        default: path(for: slug)
        }
    }
}

extension SiteConfig {
    /// The collection with this id, if site.json has it.
    func collection(_ id: String) -> ContentCollection? {
        collections.first { $0.id == id }
    }

    /// The collection a kind of page belongs to: from site.json, or a
    /// stand-in when its collection isn't there.
    func collection(for kind: ContentKind) -> ContentCollection? {
        guard let id = kind.collectionID else { return nil }
        return collection(id) ?? .fallback(id)
    }

    /// Every kind of page the site can have, in menu order: static pages,
    /// each collection's items and categories, then link menus.
    var kinds: [ContentKind] {
        [.page] + collections.flatMap { c in [c.itemKind] + (c.categories ? [c.categoryKind] : []) } + [.links]
    }

    func singularName(_ kind: ContentKind) -> String {
        switch kind {
        case .page: "Static Page"
        case .links: "Link Menu"
        case .main: "\(collection(for: kind)!.name) Main Page"
        case .item: collection(for: kind)!.itemName
        case .category: collection(for: kind)!.categoryName
        }
    }

    func pluralName(_ kind: ContentKind) -> String {
        switch kind {
        case .page: "Static Pages"
        case .links: "Link Menus"
        case .main: "\(collection(for: kind)!.name) Main Page"
        case .item: collection(for: kind)!.itemsName
        case .category: collection(for: kind)!.name + " Categories"
        }
    }

    func systemImage(_ kind: ContentKind) -> String {
        switch kind {
        case .page: "doc.text"
        case .links: "link"
        case .main: "list.bullet.rectangle"
        case .item: collection(for: kind)!.icon
        case .category: "folder"
        }
    }

    /// One line about what this type does, for pickers.
    func summary(_ kind: ContentKind) -> String {
        switch kind {
        case .page:
            return "A page on its own, like About or Contact. Link to it from the menu, the footer or other pages."
        case .links:
            return "A list of links for a drop-down menu in the footer. It isn't published as its own page."
        case .main:
            let c = collection(for: kind)!
            return "Lists every \(c.itemName.lowercased()) in \(c.name), under this page's text."
        case .item:
            let c = collection(for: kind)!
            var text = "A \(c.itemName.lowercased()) in \(c.name), listed on \(c.mainPath)"
            if c.onHome { text += ", the Home page" }
            if c.categories { text += " and the categories you choose" }
            if c.selling { text += ". It has a price and a Buy button" }
            return text + "."
        case .category:
            let c = collection(for: kind)!
            return "Lists the \(c.itemsName.lowercased()) you put in this category, under your own text."
        }
    }

    /// What the page is, in words for site visitors (shown in search results).
    func visitorTypeName(_ kind: ContentKind) -> String {
        switch kind {
        case .page, .links, .main: "Page"
        case .item: collection(for: kind)!.itemName
        case .category: "Category"
        }
    }
}

/// Tags: words put on pages (`tags:` front matter) to group them across
/// collections. Each tag gets a page at /tags/<tag>/ listing its pages, and
/// /tags/ lists them all. Saved in site.json (`tags`), edited in
/// Configuration → Tags.
struct TagSettings: Codable, Equatable, Sendable {
    /// A tag with a description, or one made before any page used it.
    struct Tag: Codable, Equatable, Sendable, Identifiable {
        var name: String
        var description = ""
        var id: String { slug }
        var slug: String { TagSettings.slug(name) }

        init(name: String, description: String = "") {
            self.name = name
            self.description = description
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        }
    }

    /// Publish /tags/ and a page for each tag.
    var pages = true
    var list: [Tag] = []

    static let path = "/tags/"
    static func path(_ slug: String) -> String { path + slug + "/" }
    /// A tag's address name: "Swift UI" → "swift-ui". Tags with the same
    /// one are the same tag.
    static func slug(_ name: String) -> String { Site.slugify(name.trimmingCharacters(in: .whitespaces)) }

    /// `tags` with one renamed; a tag already there under the new name
    /// merges with it.
    static func renaming(_ slug: String, to name: String, in tags: [String]) -> [String] {
        var result: [String] = []
        for tag in tags {
            let renamed = Self.slug(tag) == slug ? name : tag
            if !result.contains(where: { Self.slug($0) == Self.slug(renamed) }) { result.append(renamed) }
        }
        return result
    }

    /// Adds and removes tags, keeping the order and one of each.
    static func changing(_ tags: [String], adding: [String], removing: [String]) -> [String] {
        let gone = Set(removing.map(slug))
        var result = tags.filter { !gone.contains(slug($0)) }
        for tag in adding where !result.contains(where: { slug($0) == slug(tag) }) { result.append(tag) }
        return result
    }

    init() {}

    /// Renames a tag in the list, keeping its description; merges it into
    /// a tag that already has the new name.
    mutating func rename(_ slug: String, to name: String) {
        let newSlug = Self.slug(name)
        let old = list.first { $0.slug == slug }
        list.removeAll { $0.slug == slug }
        if let i = list.firstIndex(where: { $0.slug == newSlug }) {
            list[i].name = name
            if list[i].description.isEmpty { list[i].description = old?.description ?? "" }
        } else if let old {
            list.append(.init(name: name, description: old.description))
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pages = try c.decodeIfPresent(Bool.self, forKey: .pages) ?? true
        list = try c.decodeIfPresent([Tag].self, forKey: .list) ?? []
    }
}

/// Tags on files in media/ (photos and other files), which have no front
/// matter of their own. Saved in `media.json` at the site's root, which is
/// committed with the site but not published.
struct MediaTags: Equatable, Sendable {
    static let fileName = "media.json"
    /// A file's path in the site (e.g. `media/files/beach.jpg`) → its tags.
    var tags: [String: [String]] = [:]

    private struct File: Codable {
        struct Entry: Codable { var tags: [String] }
        var files: [String: Entry]
    }

    static func load(from root: URL) -> MediaTags {
        guard let data = try? Data(contentsOf: root.appending(path: fileName)),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return MediaTags() }
        return MediaTags(tags: file.files.mapValues(\.tags).filter { !$0.value.isEmpty })
    }

    /// Writes media.json, leaving out files without tags and files that
    /// are gone. With no tags left, the file is removed.
    func save(to root: URL) throws {
        let url = root.appending(path: Self.fileName)
        let kept = tags.filter { path, list in
            !list.isEmpty && FileManager.default.fileExists(atPath: root.appending(path: path).path)
        }
        guard !kept.isEmpty else {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(File(files: kept.mapValues { File.Entry(tags: $0) })).write(to: url, options: .atomic)
    }

    subscript(path: String) -> [String] {
        get { tags[path] ?? [] }
        set { tags[path] = newValue.isEmpty ? nil : newValue }
    }

    mutating func rename(_ slug: String, to name: String) {
        for (path, list) in tags { tags[path] = TagSettings.renaming(slug, to: name, in: list) }
    }

    mutating func remove(_ slug: String) {
        for (path, list) in tags { self[path] = list.filter { TagSettings.slug($0) != slug } }
    }
}

/// A tag and the pages and files that have it.
struct TagUse: Identifiable, Equatable, Sendable {
    var name: String
    var slug: String
    var description: String
    var pages: [ContentItem]
    /// Files in media/ with the tag, by path, sorted.
    var files: [String] = []

    /// "3 pages · 2 files", or "Not used".
    var usage: String {
        var parts: [String] = []
        if !pages.isEmpty { parts.append("\(pages.count) \(pages.count == 1 ? "page" : "pages")") }
        if !files.isEmpty { parts.append("\(files.count) \(files.count == 1 ? "file" : "files")") }
        return parts.isEmpty ? "Not used" : parts.joined(separator: " · ")
    }

    var isUsed: Bool { !pages.isEmpty || !files.isEmpty }
    var id: String { slug }
    var path: String { TagSettings.path(slug) }
}

extension ContentItem {
    /// The tags on this page, as written.
    var tags: [String] {
        get { frontMatter.list("tags") }
        set { frontMatter["tags"] = newValue.isEmpty ? nil : .list(newValue) }
    }

    func hasTag(_ slug: String) -> Bool { tags.contains { TagSettings.slug($0) == slug } }

    /// The tags with one renamed; when the page already has the new name,
    /// the two become one.
    func tags(renaming slug: String, to name: String) -> [String] {
        TagSettings.renaming(slug, to: name, in: tags)
    }

    /// Whether this page is listed on tag pages: published pages only, so
    /// not link menus, the Template page or the 404 page.
    var isListedOnTagPages: Bool { !isLinkMenu && !isTemplatePage && !isNotFoundPage }

    /// True for a collection's main page.
    var isCollectionMain: Bool { kind.isMain }
}

extension Site {
    /// The collection pages of this kind belong to.
    func collection(for kind: ContentKind) -> ContentCollection? { config.collection(for: kind) }

    /// A collection's main page file, if it has one.
    func mainPage(of collection: ContentCollection) -> ContentItem? {
        items.first { $0.kind == collection.mainKind }
    }

    /// Every tag: the ones in site.json and the ones on pages and files, by
    /// name. A tag written differently in different places ("iOS", "ios") is
    /// one tag, named as site.json or most places have it.
    func tagIndex(includeDrafts: Bool = true) -> [TagUse] {
        var uses: [String: TagUse] = [:]
        var spellings: [String: [String: Int]] = [:]
        for item in items where includeDrafts || !item.isDraft {
            var seen = Set<String>()
            for name in item.tags {
                let slug = TagSettings.slug(name)
                guard seen.insert(slug).inserted else { continue }
                uses[slug, default: TagUse(name: name, slug: slug, description: "", pages: [])].pages.append(item)
                spellings[slug, default: [:]][name, default: 0] += 1
            }
        }
        for (path, names) in mediaTags.tags.sorted(by: { $0.key < $1.key })
        where FileManager.default.fileExists(atPath: root.appending(path: path).path) {
            var seen = Set<String>()
            for name in names {
                let slug = TagSettings.slug(name)
                guard seen.insert(slug).inserted else { continue }
                uses[slug, default: TagUse(name: name, slug: slug, description: "", pages: [])].files.append(path)
                spellings[slug, default: [:]][name, default: 0] += 1
            }
        }
        for (slug, counts) in spellings {
            uses[slug]?.name = counts.max { a, b in a.value != b.value ? a.value < b.value : a.key > b.key }!.key
        }
        for tag in config.tags.list where !tag.name.trimmingCharacters(in: .whitespaces).isEmpty {
            uses[tag.slug, default: TagUse(name: tag.name, slug: tag.slug, description: "", pages: [])].name = tag.name
            uses[tag.slug]?.description = tag.description
        }
        return uses.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// A folder you make: a short address, like /subscribe/, that shows one of
/// your pages. The page keeps its own address (the copy at the folder tells
/// search engines which is the original); removing the folder only removes
/// the shortcut. Saved in site.json (`folders`).
struct Folder: Codable, Equatable, Sendable, Identifiable {
    /// The folder's name in the address, e.g. `subscribe`.
    var name: String
    /// The file name (slug) of the page it shows, e.g. `subscribe` for
    /// pages/subscribe.md.
    var page: String

    var id: String { name }
    var path: String { "/\(name)/" }

    /// A folder CardStock makes and uses itself.
    struct System: Identifiable, Equatable {
        var name: String
        /// What it holds, e.g. "The Shop collection".
        var detail: String
        var id: String { name }
        var path: String { "/\(name)/" }
    }
}

extension SiteConfig {
    /// The folders CardStock makes: one per collection, then the ones every
    /// site has. They can't be removed or used for anything else.
    var systemFolders: [Folder.System] {
        collections.map { Folder.System(name: $0.id, detail: "The \($0.name) collection: its main page, and its \($0.itemsName.lowercased()) and categories in /\($0.id)/pages/") }
            + [
                .init(name: ContentKind.pagesFolder, detail: "Every page that isn't in a collection, like About and Search"),
                .init(name: "tags", detail: "A page for each tag"),
                .init(name: "media", detail: "Your photos and files"),
                .init(name: "assets", detail: "Your theme's styles, fonts and scripts"),
            ]
    }

    /// Why `name` can't be a new folder, or nil when it can. `except` is a
    /// folder being edited, which may keep its name.
    func folderProblem(_ name: String, except: String? = nil) -> String? {
        if name.isEmpty { return "Type a name for the folder." }
        if name != Site.slugify(name) { return "Use lowercase letters, numbers and hyphens, like subscribe or spring-sale." }
        if let system = systemFolders.first(where: { $0.name == name }) {
            return "/\(name)/ is made by CardStock (\(system.detail.prefix(1).lowercased() + system.detail.dropFirst())), so it can't be used."
        }
        if ContentCollection.reservedIDs.contains(name) || Site.reservedSlugs.contains(name) || name.hasPrefix("_")
            || ["links", "feed", "search", "index"].contains(name) {
            return "/\(name)/ is used by CardStock. Choose another name."
        }
        if name != except, folders.contains(where: { $0.name == name }) {
            return "You already have a /\(name)/ folder."
        }
        return nil
    }

    func folder(at path: String) -> Folder? { folders.first { $0.path == path } }
}
