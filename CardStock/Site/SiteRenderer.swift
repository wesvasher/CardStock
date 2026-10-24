import Foundation
import Markdown

/// Renders a site's pages from its content and theme. Used both to build
/// `public/` and to serve the live preview.
struct SiteRenderer: Sendable {
    let site: Site
    let includeDrafts: Bool
    private let templates: [String: Template]
    /// Page layouts by id (theme/layouts).
    private let layoutTemplates: [String: Template]

    /// Templates every theme has.
    static let templateNames = ["base", "home", "page"]
    /// Templates added later: collection main and category pages, item
    /// pages and tag pages. A theme without them uses CardStock's built-in
    /// versions.
    static let newerTemplateNames = ["collection", "item", "tags"]
    /// The Template page (pages/template.md): every part of the style on one
    /// page, for the preview. Never published.
    static let templatePageTemplate = "template"
    static let templatePagePath = "/_template/"
    /// `/_layouts/<id>/` shows a sample page in a layout, for the Layouts
    /// page's preview (`standard` is the type's own template). Never published.
    static let layoutPreviewPrefix = "/_layouts/"
    static func layoutPreviewPath(_ id: String) -> String { layoutPreviewPrefix + (id.isEmpty ? "standard" : id) + "/" }
    /// A sample page with the newsletter box, for Configuration → Mailing List's
    /// preview. Never published.
    static let newsletterPreviewPath = "/_newsletter/"
    /// The Search page's template (pages/search.md, at /search/).
    static let searchTemplate = "search"
    /// What the Search page searches: every findable page as JSON.
    static let searchIndexPath = "/search.json"

    init(site: Site, includeDrafts: Bool = false) throws {
        self.site = site
        self.includeDrafts = includeDrafts
        var templates: [String: Template] = [:]
        for name in Self.templateNames + Self.newerTemplateNames + [Self.templatePageTemplate, Self.searchTemplate] {
            let url = site.root.appending(path: "theme/\(name).html")
            if let source = try? String(contentsOf: url, encoding: .utf8) {
                templates[name] = try Template(source, name: "theme/\(name).html")
            } else if !Self.templateNames.contains(name), let source = Self.builtInTemplate(name) {
                templates[name] = try Template(source, name: "theme/\(name).html")
            } else {
                throw SiteError("The theme is missing theme/\(name).html.")
            }
        }
        self.templates = templates
        var layoutTemplates: [String: Template] = [:]
        for layout in site.layouts {
            layoutTemplates[layout.id] = try Template(layout.source, name: "\(PageLayout.folder)/\(layout.id).html")
        }
        self.layoutTemplates = layoutTemplates
    }

    /// A template from the starter site in CardStock's bundle.
    static func builtInTemplate(_ name: String) -> String? {
        guard let url = Bundle.main.url(forResource: "StarterSite", withExtension: nil)?
            .appending(path: "theme/\(name).html") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func published(_ kind: ContentKind) -> [ContentItem] {
        site.items(kind).filter { includeDrafts || !$0.isDraft }
    }

    /// Every path the site publishes.
    var paths: [String] {
        var paths = ["/", "/feed.xml"]
        // Link menus only appear inside the footer; the Template page
        // only in the preview.
        for item in site.items where item.kind != .links && (includeDrafts || !item.isDraft)
            && !item.isHome && !item.isTemplatePage && !(item.isSearchPage && !site.config.search.enabled) {
            paths.append(item.path)
        }
        // Main pages without a file of their own, once there's something to list.
        for c in allCollections where site.mainPage(of: c) == nil && !items(of: c).isEmpty {
            paths.append(c.mainPath)
        }
        if site.config.tags.pages {
            let tags = publishedTags
            if !tags.isEmpty { paths += [TagSettings.path] + tags.map(\.path) }
        }
        if site.config.search.enabled { paths.append(Self.searchIndexPath) }
        return paths
    }

    /// Renders one path, or returns nil when nothing lives there.
    func render(path: String) -> String? {
        switch path {
        case "/", "/index.html":
            return renderHome()
        case "/feed.xml":
            return renderFeed()
        case Self.templatePagePath where !site.items.contains(where: \.isTemplatePage):
            // Sites without pages/template.md still get the page in the preview.
            let context = globals(path: path, title: "Template", description: nil)
            return wrap(templates[Self.templatePageTemplate]!.render(.dict(context)), context: context)
        case Self.newsletterPreviewPath:
            return render(newsletterSample())
        case Self.searchIndexPath:
            return searchIndexJSON()
        case "/\(ContentItem.searchSlug)/" where !site.items.contains(where: \.isSearchPage):
            // Sites without pages/search.md still get the page.
            return render(ContentItem(fileURL: site.root.appending(path: "pages/search.md"),
                                      text: "---\ntitle: Search\n---\n"))
        case _ where path.hasPrefix(Self.layoutPreviewPrefix):
            let id = path.dropFirst(Self.layoutPreviewPrefix.count).split(separator: "/").first.map(String.init) ?? ""
            return render(layoutSample(id == "standard" ? "" : id))
        default:
            let normalized = path.hasSuffix("/index.html") ? String(path.dropLast("index.html".count)) : path
            if normalized.hasPrefix(TagSettings.path), site.config.tags.pages || includeDrafts {
                let slug = normalized.dropFirst(TagSettings.path.count).split(separator: "/").first.map(String.init)
                return renderTag(slug)
            }
            if let item = site.items.first(where: { (includeDrafts || !$0.isDraft) && $0.path == normalized }) {
                return render(item)
            }
            if let c = allCollections.first(where: { $0.mainPath == normalized }),
               site.mainPage(of: c) == nil, includeDrafts || !items(of: c).isEmpty {
                return render(mainPage(of: c))
            }
            return nil
        }
    }

    func render(_ item: ContentItem) -> String {
        if item.isHome { return renderHome(item) }
        let collection = site.collection(for: item.kind)
        let template: String
        switch item.kind {
        case .page where item.isTemplatePage: template = Self.templatePageTemplate
        case .page where item.isSearchPage: template = Self.searchTemplate
        case .page, .links: template = "page"
        case .main, .category: template = "collection"
        case .item: template = "item"
        }
        var context = globals(path: item.path, title: item.title, description: item.frontMatter.string("summary"))
        if case .dict(var page) = itemValue(item), case .dict(let meta)? = context["page"] {
            page.merge(meta) { itemField, _ in itemField }
            context["page"] = .dict(page)
        }
        if item.isSearchPage {
            let search = site.config.search
            context["search"] = .dict([
                "index": .string(Self.searchIndexPath),
                "placeholder": .string(search.shownPlaceholder),
                "buttonLabel": .string(search.shownButtonLabel),
            ])
        }
        if let collection {
            context["collection"] = collectionValue(collection)
            switch item.kind {
            case .main, .category:
                // Main pages list every item; categories the ones put in them.
                let listed = item.kind.isMain ? items(of: collection) : members(of: item)
                context["items"] = .list(listed.map { cardValue($0, collection) })
                context["listing"] = .string(listingHTML(listed, collection))
                context["categoryNav"] = .string(categoryNavHTML(collection, current: item.path))
            case .item:
                context["item"] = itemPageValue(item, collection)
            default:
                break
            }
        }
        if let layout = layout(for: item) {
            return renderLayout(item, layout, context: context)
        }
        return wrap(templates[template]!.render(.dict(context)), context: context)
    }

    // MARK: - Collections

    /// The site's collections, plus stand-ins for any that pages name but
    /// site.json doesn't have.
    var allCollections: [ContentCollection] {
        var list = site.config.collections
        for item in site.items {
            if let id = item.kind.collectionID, !list.contains(where: { $0.id == id }) {
                list.append(.fallback(id))
            }
        }
        return list
    }

    /// A collection's published items, in its order.
    func items(of collection: ContentCollection) -> [ContentItem] {
        Self.sorted(published(collection.itemKind), collection.sort)
    }

    static func sorted(_ items: [ContentItem], _ sort: ContentCollection.Sort) -> [ContentItem] {
        func byTitle(_ a: ContentItem, _ b: ContentItem) -> Bool {
            a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
        switch sort {
        case .newest: return items.sorted { $0.date != $1.date ? $0.date > $1.date : byTitle($0, $1) }
        case .oldest: return items.sorted { $0.date != $1.date ? $0.date < $1.date : byTitle($0, $1) }
        case .title: return items.sorted(by: byTitle)
        }
    }

    /// A collection's main page: its file, or one made from its name.
    func mainPage(of collection: ContentCollection) -> ContentItem {
        site.mainPage(of: collection) ?? ContentItem(
            fileURL: site.root.appending(path: "pages/\(collection.id).md"),
            text: "---\ntitle: \(collection.name)\ntype: \(ContentKind.mainType)\n---\n")
    }

    /// Items listed on the Home page: those of every collection shown
    /// there, newest first.
    var homeItems: [ContentItem] {
        let ids = Set(site.config.collections.filter(\.onHome).map(\.id))
        return Self.sorted(site.items.filter { item in
            guard case .item(let c) = item.kind else { return false }
            return ids.contains(c) && (includeDrafts || !item.isDraft)
        }, .newest)
    }

    private func collectionValue(_ c: ContentCollection) -> TemplateValue {
        .dict([
            "id": .string(c.id),
            "name": .string(c.name),
            "itemName": .string(c.itemName),
            "itemsName": .string(c.itemsName),
            "url": .string(c.mainPath),
            "list": .bool(c.listStyle == .list),
            "cards": .bool(c.listStyle == .cards),
            "gallery": .bool(c.listStyle == .gallery),
            "columns": .string(String(Self.columns(c))),
            "selling": .bool(c.selling),
            "emptyText": .string(c.shownEmptyText),
        ])
    }

    private static func columns(_ c: ContentCollection) -> Int { min(max(c.columns, 1), 6) }

    /// An item as a list entry, with only the fields the collection lists.
    private func cardValue(_ item: ContentItem, _ c: ContentCollection) -> TemplateValue {
        var dict: [String: TemplateValue] = [
            "title": .string(item.title),
            "url": .string(item.path),
            "slug": .string(item.slug),
            "draft": .bool(item.isDraft),
        ]
        if c.listDates && !item.date.isEmpty {
            dict["date"] = .string(item.date)
            dict["dateDisplay"] = .string(displayDate(item.date))
        }
        if c.listSummaries { dict["summary"] = .string(item.frontMatter.string("summary") ?? "") }
        if c.listImages { dict["image"] = .string(listImage(item, c)) }
        if c.selling { dict["price"] = .string(item.frontMatter.string("price") ?? "") }
        return .dict(dict)
    }

    /// The picture for an item in lists: its cover, else its video's thumbnail.
    private func listImage(_ item: ContentItem, _ c: ContentCollection) -> String {
        let cover = item.frontMatter.string("cover") ?? ""
        if !cover.isEmpty { return cover }
        if c.video { return Self.videoThumbnail(item.frontMatter.string("video") ?? "") ?? "" }
        return ""
    }

    /// An item page's values: everything `itemValue` has, plus `meta` (date,
    /// categories and tags, and the price), `actions` (the Buy button),
    /// `videoEmbed` and `pager`, each as HTML and empty when the collection
    /// leaves it out. `cover` is empty when covers are off.
    private func itemPageValue(_ item: ContentItem, _ c: ContentCollection) -> TemplateValue {
        guard case .dict(var dict) = itemValue(item) else { return itemValue(item) }
        dict["meta"] = .string(metaHTML(item))
        dict["actions"] = .string(actionsHTML(item))
        dict["videoEmbed"] = .string(c.video ? Self.videoEmbedHTML(item.frontMatter.string("video") ?? "") : "")
        dict["pager"] = .string(pagerHTML(item, c))
        if !c.showCover { dict["cover"] = .string("") }
        return .dict(dict)
    }

    /// Links to the previous and next item, and to the main page.
    private func pagerHTML(_ item: ContentItem, _ c: ContentCollection) -> String {
        guard c.prevNext else { return "" }
        let list = items(of: c)
        let index = list.firstIndex { $0.id == item.id }
        let before = index.flatMap { $0 > 0 ? list[$0 - 1] : nil }
        let after = index.flatMap { $0 + 1 < list.count ? list[$0 + 1] : nil }
        let (beforeLabel, afterLabel) = c.sort == .newest && c.dated ? ("Newer", "Older") : ("Previous", "Next")
        func link(_ item: ContentItem?, _ label: String, _ cls: String) -> String {
            guard let item else { return #"<span class="\#(cls)"></span>"# }
            return #"<a class="\#(cls)" href="\#(escapeHTML(item.path))"><small>\#(label)</small>\#(escapeHTML(item.title))</a>"#
        }
        return #"<nav class="pager" aria-label="More \#(escapeHTML(c.itemsName.lowercased()))">"#
            + link(before, beforeLabel, "prev")
            + #"<a class="all" href="\#(escapeHTML(c.mainPath))">All \#(escapeHTML(c.itemsName.lowercased()))</a>"#
            + link(after, afterLabel, "next") + "</nav>"
    }

    /// Items as the collection lists them: rows, cards or a gallery.
    func listingHTML(_ items: [ContentItem], _ c: ContentCollection) -> String {
        guard !items.isEmpty else { return #"<p class="empty">\#(escapeHTML(c.shownEmptyText))</p>"# }
        let price = { (item: ContentItem) -> String in
            let p = c.selling ? item.frontMatter.string("price") ?? "" : ""
            return p.isEmpty ? "" : #"<p class="price">\#(escapeHTML(p))</p>"#
        }
        let summary = { (item: ContentItem) -> String in
            let s = c.listSummaries ? item.frontMatter.string("summary") ?? "" : ""
            return s.isEmpty ? "" : "<p>\(escapeHTML(s))</p>"
        }
        let date = { (item: ContentItem) -> String in
            guard c.listDates, !item.date.isEmpty else { return "" }
            return #"<time datetime="\#(escapeHTML(item.date))">\#(escapeHTML(displayDate(item.date)))</time>"#
        }
        let style = #"style="--cols:\#(Self.columns(c))""#
        switch c.listStyle {
        case .list:
            let rows = items.map { item in
                #"<li><a href="\#(escapeHTML(item.path))">\#(escapeHTML(item.title))</a> "# + date(item) + price(item) + summary(item) + "</li>"
            }
            return #"<ul class="post-list">"# + rows.joined() + "</ul>"
        case .cards:
            let cards = items.map { item in
                var card = #"<a class="project-card" href="\#(escapeHTML(item.path))">"#
                let image = c.listImages ? listImage(item, c) : ""
                if !image.isEmpty { card += #"<img src="\#(escapeHTML(image))" alt="">"# }
                card += "<h2>\(escapeHTML(item.title))</h2>" + price(item) + date(item) + summary(item)
                return card + "</a>"
            }
            return #"<div class="project-grid collection-grid" \#(style)>"# + cards.joined() + "</div>"
        case .gallery:
            let tiles = items.map { item in
                let image = listImage(item, c)
                let picture = image.isEmpty ? #"<span class="gallery-blank"></span>"#
                    : #"<img src="\#(escapeHTML(image))" alt="" loading="lazy">"#
                return #"<a class="gallery-item" href="\#(escapeHTML(item.path))">"# + picture
                    + "<span>\(escapeHTML(item.title))</span>" + date(item) + "</a>"
            }
            return #"<div class="collection-grid collection-gallery" \#(style)>"# + tiles.joined() + "</div>"
        }
    }

    /// Links to the main page and each category, above a list.
    private func categoryNavHTML(_ c: ContentCollection, current: String) -> String {
        guard c.categories, c.listCategories else { return "" }
        let categories = published(c.categoryKind)
        guard !categories.isEmpty else { return "" }
        func link(_ title: String, _ path: String) -> String {
            let here = path == current ? #" aria-current="page""# : ""
            return #"<li><a href="\#(escapeHTML(path))"\#(here)>\#(escapeHTML(title))</a></li>"#
        }
        return #"<ul class="category-links">"# + link("All", c.mainPath)
            + categories.map { link($0.title, $0.path) }.joined() + "</ul>"
    }

    // MARK: - Tags

    /// Every tag with only what's published under it (pages that have an
    /// address of their own, and files), without unused ones.
    var publishedTags: [TagUse] { tagsWithPublishedPages.filter(\.isUsed) }

    /// Every tag, with only its published pages.
    private var tagsWithPublishedPages: [TagUse] {
        site.tagIndex(includeDrafts: includeDrafts).map { tag in
            var tag = tag
            tag.pages = tag.pages.filter { $0.isListedOnTagPages && !($0.isSearchPage && !site.config.search.enabled) }
            return tag
        }
    }

    /// /tags/ (every tag) or /tags/<slug>/ (one tag's pages).
    private func renderTag(_ slug: String?) -> String? {
        let tags = tagsWithPublishedPages
        var context: [String: TemplateValue]
        if let slug {
            guard let tag = tags.first(where: { $0.slug == slug }) else { return nil }
            context = globals(path: tag.path, title: tag.name,
                              description: tag.description.isEmpty ? nil : tag.description)
            context["tag"] = .dict([
                "name": .string(tag.name),
                "description": .string(tag.description),
                "count": .string(tag.usage),
            ])
            context["listing"] = .string(tagListingHTML(tag.pages, files: tag.files))
        } else {
            context = globals(path: TagSettings.path, title: "Tags", description: nil)
        }
        context["tags"] = .list(tags.filter(\.isUsed).map { tag in
            .dict(["name": .string(tag.name), "url": .string(tag.path), "count": .string(String(tag.pages.count + tag.files.count))])
        })
        return wrap(templates["tags"]!.render(.dict(context)), context: context)
    }

    /// A tag's pages (title, what it is, date and summary), then its photos
    /// as a gallery and its other files as links.
    func tagListingHTML(_ pages: [ContentItem], files: [String] = []) -> String {
        guard !pages.isEmpty || !files.isEmpty else { return #"<p class="empty">Nothing has this tag yet.</p>"# }
        var html = pages.isEmpty ? "" : tagPagesHTML(pages)
        let images = files.filter { ImageImporter.isImage(URL(filePath: $0)) }
        let others = files.filter { !images.contains($0) }
        let headings = !pages.isEmpty
        if !images.isEmpty {
            if headings { html += #"<h2 class="tag-heading">Photos</h2>"# }
            html += #"<div class="collection-grid collection-gallery tag-photos" style="--cols:4">"#
            for path in images {
                var shown = path
                if let small = MediaLibrary.smallPath(for: path),
                   FileManager.default.fileExists(atPath: site.root.appending(path: small).path) {
                    shown = small
                }
                html += #"<a class="gallery-item" href="/\#(escapeHTML(path))"><img src="/\#(escapeHTML(shown))" alt="" loading="lazy"></a>"#
            }
            html += "</div>"
        }
        if !others.isEmpty {
            if headings || !images.isEmpty { html += #"<h2 class="tag-heading">Files</h2>"# }
            html += #"<ul class="post-list tag-list">"# + others.map { path in
                #"<li><a href="/\#(escapeHTML(path))">\#(escapeHTML((path as NSString).lastPathComponent))</a></li>"#
            }.joined() + "</ul>"
        }
        return html
    }

    private func tagPagesHTML(_ pages: [ContentItem]) -> String {
        let rows = Self.sorted(pages, .newest).map { item in
            var row = #"<li><a href="\#(escapeHTML(item.path))">\#(escapeHTML(item.title))</a> "#
            var meta = [site.config.visitorTypeName(item.kind)]
            if item.kind.isItem, site.collection(for: item.kind)?.dated == true, !item.date.isEmpty {
                meta.append(displayDate(item.date))
            }
            row += #"<span class="meta">\#(escapeHTML(meta.joined(separator: " · ")))</span>"#
            let summary = item.frontMatter.string("summary") ?? ""
            if !summary.isEmpty { row += "<p>\(escapeHTML(summary))</p>" }
            return row + "</li>"
        }
        return #"<ul class="post-list tag-list">"# + rows.joined() + "</ul>"
    }

    /// A page's tags as links to their tag pages (or plain words when tag
    /// pages are off).
    private func tagLinksHTML(_ item: ContentItem) -> String {
        item.tags.map { name in
            let slug = TagSettings.slug(name)
            return site.config.tags.pages
                ? #"<a class="tag" href="\#(escapeHTML(TagSettings.path(slug)))">\#(escapeHTML(name))</a>"#
                : #"<span class="tag">\#(escapeHTML(name))</span>"#
        }.joined()
    }

    /// The home page: home.html with the post list, plus the Home page's
    /// fields and text as `page` when pages/index.md exists.
    private func renderHome(_ homeItem: ContentItem? = nil) -> String {
        let home = homeItem ?? site.home
        let description = home?.frontMatter.string("summary") ?? site.config.description
        var context = globals(path: "/", title: home?.title ?? site.config.title, description: description)
        if let home, case .dict(var page) = itemValue(home), case .dict(let meta)? = context["page"] {
            page.merge(meta) { _, globalField in globalField }
            context["page"] = .dict(page)
        }
        context["posts"] = .list(homeItems.map(itemValue))
        if let home, let layout = layout(for: home) {
            return renderLayout(home, layout, context: context)
        }
        return wrap(templates["home"]!.render(.dict(context)), context: context)
    }

    // MARK: - Layouts

    /// The page's chosen layout, or nil for its type's standard template
    /// (also when the chosen layout isn't in theme/layouts).
    func layout(for item: ContentItem) -> PageLayout? {
        guard !item.layout.isEmpty, !item.isTemplatePage, !item.isSearchPage else { return nil }
        return site.layouts.first { $0.id == item.layout }
    }

    /// Renders a page in a layout. Besides the usual values, the layout gets
    /// `section.1`, `section.2`, … (the text for each area), `page.sections`
    /// (every section), `page.meta` and `page.actions` (the type's details,
    /// such as a post's date or a product's price and Buy button),
    /// `page.listing` (a category's posts or products, or Home's posts),
    /// `recentPosts` and `blogCategories`.
    private func renderLayout(_ item: ContentItem, _ layout: PageLayout, context: [String: TemplateValue]) -> String {
        guard let template = layoutTemplates[layout.id] else { return "" }
        var context = context
        var page: [String: TemplateValue] = [:]
        if case .dict(let d)? = context["page"] { page = d }
        if case .dict(let fields) = itemValue(item) { page.merge(fields) { current, _ in current } }
        let sections = PageLayout.sections(of: item.body)
        page["sections"] = .list(sections.filter { !$0.isEmpty }.map { .string(Self.markdownToHTML($0)) })
        page["meta"] = .string(metaHTML(item))
        page["actions"] = .string(actionsHTML(item))
        page["listing"] = .string(listingHTML(item))
        context["page"] = .dict(page)
        var areas: [String: TemplateValue] = [:]
        for (number, text) in layout.areaText(sections) {
            areas[String(number)] = .string(Self.markdownToHTML(text))
        }
        context["section"] = .dict(areas)
        context["recentPosts"] = .list(homeItems.prefix(5).map(itemValue))
        context["blogCategories"] = .list(published(.blogCategory).map(itemValue))
        if let c = site.collection(for: item.kind), c.categories {
            context["categories"] = .list(published(c.categoryKind).map(itemValue))
        }
        return wrap(template.render(.dict(context)), context: context)
    }

    /// Shown above an item's text: its date, categories and tags (each
    /// when the collection shows them), and its price.
    private func metaHTML(_ item: ContentItem) -> String {
        guard item.kind.isItem, let c = site.collection(for: item.kind) else { return "" }
        var parts: [String] = []
        if c.dated && c.showDate && !item.date.isEmpty {
            parts.append(#"<time datetime="\#(escapeHTML(item.date))">\#(escapeHTML(displayDate(item.date)))</time>"#)
        }
        if c.categories && c.showCategories {
            let categories = categoryLinksHTML(item)
            if !categories.isEmpty { parts.append(categories) }
        }
        if c.showTags {
            let tags = tagLinksHTML(item)
            if !tags.isEmpty { parts.append(tags) }
        }
        var html = parts.isEmpty ? "" : #"<p class="meta">"# + parts.joined(separator: " · ") + "</p>"
        let price = c.selling ? item.frontMatter.string("price") ?? "" : ""
        if !price.isEmpty { html += #"<p class="price">\#(escapeHTML(price))</p>"# }
        return html
    }

    /// Shown below an item's text: the Buy button, when it's for sale.
    private func actionsHTML(_ item: ContentItem) -> String {
        guard item.kind.isItem, site.collection(for: item.kind)?.selling == true else { return "" }
        let buy = item.frontMatter.string("buy") ?? ""
        guard !buy.isEmpty else { return "" }
        let label = item.frontMatter.string("buyLabel").flatMap { $0.isEmpty ? nil : $0 } ?? "Buy Now"
        return #"<p><a class="button buy" href="\#(escapeHTML(buy))" target="_blank" rel="noopener">\#(escapeHTML(label))</a></p>"#
    }

    private func categoryLinksHTML(_ item: ContentItem) -> String {
        guard case .item(let id) = item.kind else { return "" }
        let categories = published(.category(id))
        return item.categories.compactMap { slug in
            categories.first { $0.slug == slug }.map {
                #"<a class="category" href="\#(escapeHTML($0.path))">\#(escapeHTML($0.title))</a>"#
            }
        }.joined()
    }

    /// For layouts: a main page's or category's items, or Home's.
    private func listingHTML(_ item: ContentItem) -> String {
        if item.isHome {
            let blog = site.config.collections.first(where: \.onHome) ?? ContentCollection(preset: .blog, id: ContentCollection.blogID)
            var list = blog
            list.listStyle = .list
            return listingHTML(homeItems, list)
        }
        guard let c = site.collection(for: item.kind) else { return "" }
        switch item.kind {
        case .main: return categoryNavHTML(c, current: item.path) + listingHTML(items(of: c), c)
        case .category: return categoryNavHTML(c, current: item.path) + listingHTML(members(of: item), c)
        default: return ""
        }
    }

    /// A sample page in a layout, for the Layouts page's preview.
    /// The page shown in Configuration → Mailing List's preview.
    func newsletterSample() -> ContentItem {
        let text = """
        ---
        title: Mailing List
        summary: A sample page for previewing the mailing list sign-up box.
        ---

        Text on a page goes around the sign-up box. Put it anywhere in a page with the envelope button in the formatting bar.

        \(SiteConfig.Newsletter.marker)

        More text can follow it.
        """
        return ContentItem(fileURL: site.root.appending(path: "pages/_newsletter-sample.md"), text: text)
    }

    func layoutSample(_ id: String) -> ContentItem {
        let text = """
        ---
        title: Sample Page
        summary: A sample page for previewing layouts.
        layout: \(id)
        ---

        This is the first section. In a layout with more than one area, it fills the first one, such as the intro over a hero image. Without section breaks, all of a page's text goes into the layout's main area.

        \(PageLayout.sectionBreak)

        ## The second section

        Text after a section break fills the next area. It can hold anything Markdown can: **bold**, *italic*, [links](/) and lists.

        - One thing
        - Another thing

        \(PageLayout.sectionBreak)

        ## The third section

        A third area, such as the right-hand column or the sidebar.
        """
        return ContentItem(fileURL: site.root.appending(path: "pages/_layout-sample.md"), text: text)
    }

    private func wrap(_ body: String, context: [String: TemplateValue]) -> String {
        var context = context
        context["body"] = .string(insertWidgets(into: body))
        var html = Lightbox.inject(into: templates["base"]!.render(.dict(context)))
        // Styles for lists, galleries, pagers and videos, on pages that have them.
        if Self.collectionMarkers.contains(where: body.contains),
           let head = html.range(of: "</head>", options: .caseInsensitive) {
            html.insert(contentsOf: Self.collectionStyle, at: head.lowerBound)
        }
        // Theming settings go last in <head> so they override the theme's CSS.
        guard let theme = site.theme, let head = html.range(of: "</head>", options: .caseInsensitive) else { return html }
        return html.replacingCharacters(in: head.lowerBound..<head.lowerBound,
                                        with: theme.including(site.webFonts).headHTML)
    }

    // MARK: - Values

    private func globals(path: String, title: String, description: String?) -> [String: TemplateValue] {
        let c = site.config
        func links(_ list: [SiteConfig.NavLink]) -> TemplateValue {
            .list(list.map { link in
                let current = path == link.url
                    || (link.url != "/" && link.url.hasPrefix("/") && path.hasPrefix(link.url))
                    || (link.url == "/" && path.hasPrefix("/posts/"))
                    // A collection's main page, on its items' pages.
                    || c.collections.contains { link.url == $0.mainPath && path.hasPrefix("/\(ContentCollection.itemFolder($0.id))/") }
                let icon = NavIcon.named(link.icon)
                let title = link.title.trimmingCharacters(in: .whitespaces)
                return .dict([
                    "title": .string(title),
                    "url": .string(link.url),
                    "current": .bool(current),
                    "button": .bool(link.button),
                    // Inline SVG, empty without an icon.
                    "icon": .string(icon?.svg ?? ""),
                    // For icon-only links, read aloud instead of the text.
                    "label": .string(title.isEmpty ? (icon?.name ?? link.url) : ""),
                ])
            })
        }
        let h = c.header
        var header = headerValue(c)
        if case .dict(var values) = header {
            values["left"] = links(h.showLeftLinks ? h.leftLinks : [])
            values["center"] = links(h.showCenterLinks ? h.centerLinks : [])
            values["right"] = links(h.showRightLinks ? c.nav : [])
            // The phone menu, when it's on and there are links to put in it.
            values["mobileMenu"] = .bool(h.mobileMenu && !c.menuLinks.isEmpty)
            header = .dict(values)
        }
        return [
            "site": .dict([
                "title": .string(c.title),
                "description": .string(c.description),
                "author": .string(c.author),
                "url": .string(c.baseURL),
                "language": .string(c.language),
            ]),
            "nav": links(h.showRightLinks ? c.nav : []),
            "header": header,
            "footer": .dict([
                "enabled": .bool(c.footer.enabled),
                "copyright": .string(c.copyrightText()),
                "links": .list(c.footer.links.map { .dict(["title": .string($0.title), "url": .string($0.url)]) }),
                "rss": .bool(c.footer.showFeed),
                "logo": footerLogo(c),
                "menus": footerMenus(c),
                // Empty when off, so {{#if footer.attribution}} hides it.
                "attribution": c.footer.attribution.enabled
                    ? .dict(["text": .string(c.footer.attribution.shownText),
                             "url": .string(SiteConfig.Footer.Attribution.url)])
                    : .dict([:]),
            ]),
            "page": .dict([
                "title": .string(title),
                "isHome": .bool(path == "/"),
                "description": .string(description ?? c.description),
                "url": .string(path),
            ]),
            "year": .string(String(Calendar.current.component(.year, from: .now))),
        ]
    }

    private func itemValue(_ item: ContentItem) -> TemplateValue {
        var dict: [String: TemplateValue] = [:]
        for entry in item.frontMatter.entries {
            switch entry.value {
            case .string(let s): dict[entry.key] = .string(s)
            case .bool(let b): dict[entry.key] = .bool(b)
            case .list(let l): dict[entry.key] = .list(l.map { .string($0) })
            }
        }
        dict["title"] = .string(item.title)
        dict["slug"] = .string(item.slug)
        dict["url"] = .string(item.path)
        dict["date"] = .string(item.date)
        dict["dateDisplay"] = .string(displayDate(item.date))
        dict["summary"] = .string(item.frontMatter.string("summary") ?? "")
        dict["tags"] = .list(item.frontMatter.list("tags").map { .string($0) })
        dict["type"] = .string(item.kind.rawValue)
        dict["tagLinks"] = .list(item.tags.map { name in
            .dict(["title": .string(name), "url": .string(TagSettings.path(TagSettings.slug(name)))])
        })
        if case .item(let id) = item.kind {
            // The categories it's in, as links (unknown or draft ones left out).
            let categories = published(.category(id))
            dict["categoryLinks"] = .list(item.categories.compactMap { slug in
                categories.first { $0.slug == slug }.map { .dict(["title": .string($0.title), "url": .string($0.path)]) }
            })
        }
        if item.kind.isItem, site.collection(for: item.kind)?.selling == true {
            dict["price"] = .string(item.frontMatter.string("price") ?? "")
            dict["buy"] = .string(item.frontMatter.string("buy") ?? "")
            let label = item.frontMatter.string("buyLabel") ?? ""
            dict["buyLabel"] = .string(label.isEmpty ? "Buy Now" : label)
        }
        dict["content"] = .string(Self.markdownToHTML(item.body))
        return .dict(dict)
    }

    static func markdownToHTML(_ markdown: String) -> String {
        HTMLFormatter.format(SiteConfig.Newsletter.markPlaces(in: markdown))
    }

    private static let isoDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func displayDate(_ iso: String) -> String {
        guard let date = Self.isoDate.date(from: iso) else { return iso }
        let f = DateFormatter()
        f.locale = Locale(identifier: site.config.language)
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate("MMMMdyyyy")
        return f.string(from: date)
    }

    // MARK: - Feed

    private func renderFeed() -> String {
        let c = site.config
        let rfc822 = DateFormatter()
        rfc822.locale = Locale(identifier: "en_US_POSIX")
        rfc822.timeZone = TimeZone(identifier: "UTC")
        rfc822.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"

        var xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
        <channel>
        <title>\(escapeHTML(c.title))</title>
        <link>\(escapeHTML(c.baseURL))/</link>
        <description>\(escapeHTML(c.description))</description>
        <language>\(escapeHTML(c.language))</language>
        <atom:link href="\(escapeHTML(c.baseURL))/feed.xml" rel="self" type="application/rss+xml"/>

        """
        let fed = Set(site.config.collections.filter(\.inFeed).map(\.id))
        let posts = Self.sorted(site.items.filter { item in
            guard case .item(let c) = item.kind else { return false }
            return fed.contains(c) && (includeDrafts || !item.isDraft)
        }, .newest)
        for post in posts.prefix(20) {
            let link = c.baseURL + post.path
            let html = Self.markdownToHTML(post.body).replacingOccurrences(of: "]]>", with: "]]]]><![CDATA[>")
            xml += "<item>\n"
            xml += "<title>\(escapeHTML(post.title))</title>\n"
            xml += "<link>\(escapeHTML(link))</link>\n"
            xml += "<guid>\(escapeHTML(link))</guid>\n"
            if let date = Self.isoDate.date(from: post.date) {
                xml += "<pubDate>\(rfc822.string(from: date))</pubDate>\n"
            }
            xml += "<description><![CDATA[\(html)]]></description>\n"
            xml += "</item>\n"
        }
        xml += "</channel>\n</rss>\n"
        return xml
    }
}

extension SiteRenderer {
    /// The footer logo for templates: `src`, `alt`, `style` (its size),
    /// `left` or `below`, and `rowStyle` (padding for the row below).
    func footerLogo(_ c: SiteConfig) -> TemplateValue {
        let logo = c.footer.logo
        guard logo.hasImage else { return .dict([:]) }
        var src = logo.image.trimmingCharacters(in: .whitespaces)
        if !src.hasPrefix("/") && !src.contains("://") { src = "/" + src }
        var style: [String] = []
        if logo.width > 0 { style.append("width:\(logo.width)px") }
        if logo.height > 0 { style.append("height:\(logo.height)px") }
        return .dict([
            "src": .string(src),
            "alt": .string(logo.alt.isEmpty ? c.title : logo.alt),
            "style": .string(style.joined(separator: ";")),
            "left": .bool(logo.placement == .left),
            "below": .bool(logo.placement == .below),
            "rowStyle": .string("padding-top:\(max(logo.paddingTop, 0))px;padding-bottom:\(max(logo.paddingBottom, 0))px"),
        ])
    }
}

extension SiteRenderer {
    /// The footer's drop-down menus for templates: each has `title` and
    /// `links` (`title`, `url`, `external`). Menus whose page is missing or
    /// has no links are left out.
    func footerMenus(_ c: SiteConfig) -> TemplateValue {
        .list(c.footer.menus.compactMap { menu -> TemplateValue? in
            guard let page = site.items(.links).first(where: { $0.slug == menu.page }) else { return nil }
            let links = LinkMenu.links(in: page.body)
            guard !links.isEmpty else { return nil }
            let title = menu.title.trimmingCharacters(in: .whitespaces)
            return .dict([
                "title": .string(title.isEmpty ? page.title : title),
                "links": .list(links.map { link in
                    .dict(["title": .string(link.title), "url": .string(link.url), "external": .bool(link.isExternal)])
                }),
            ])
        })
    }
}

extension SiteRenderer {
    /// The published items in a category page, in the collection's order.
    func members(of category: ContentItem) -> [ContentItem] {
        guard case .category(let id) = category.kind else { return [] }
        let sort = site.collection(for: category.kind)?.sort ?? .newest
        return Self.sorted(site.items(.item(id))
            .filter { includeDrafts || !$0.isDraft }
            .filter { $0.categories.contains(category.slug) }, sort)
    }
}

extension SiteRenderer {
    /// The top bar for templates: `fixed` (fixed or shrinking), `shrinks`,
    /// `logo` and `compactLogo` (addresses, empty when unset), `logoAlt`,
    /// `logoWidth` (true when a width is set), `showTitle`, `brandLeft`,
    /// `brandCenter` or `brandRight` (where the logo and title go),
    /// `brandStyle` (their padding, empty when none) and `style`, the CSS
    /// variables for its sizes. `globals` adds the link groups `left`,
    /// `center` and `right`.
    func headerValue(_ c: SiteConfig) -> TemplateValue {
        let h = c.header
        func src(_ path: String) -> String {
            let path = path.trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else { return "" }
            return path.hasPrefix("/") || path.contains("://") ? path : "/" + path
        }
        let shrinks = h.mode == .shrinking
        let compactHeight = shrinks ? min(h.compactHeight, h.height) : h.height
        let compactLogoHeight = shrinks ? h.compactLogoHeight : h.logoHeight
        let compactLogo = shrinks && h.isLogoShown ? src(h.compactLogo) : ""
        let logoHeight = max(h.logoHeight, 8)
        let compactLogoH = max(compactLogoHeight, 8)
        // Logo widths only apply to images CardStock can size; SVGs follow their shape.
        let logoWidth = h.isLogoShown && !h.logo.lowercased().hasSuffix(".svg") ? max(h.logoWidth, 0) : 0
        var style = "--bar-h:\(max(h.height, 24))px;--bar-h-compact:\(max(compactHeight, 24))px;"
            + "--logo-h:\(logoHeight)px;--logo-h-compact:\(compactLogoH)px"
        if compactLogoH != logoHeight {
            style += ";--logo-k:\(Self.ratio(Double(compactLogoH) / Double(logoHeight)))"
        }
        if logoWidth > 0 { style += ";--logo-w:\(logoWidth)px" }
        let p = h.logoPadding
        let brandStyle = p.isZero ? ""
            : "padding:\(max(p.top, 0))px \(max(p.right, 0))px \(max(p.bottom, 0))px \(max(p.left, 0))px"
        let alt = h.logoAlt.trimmingCharacters(in: .whitespaces)
        let hasBrand = h.isLogoShown || h.showTitle
        return .dict([
            "mode": .string(h.mode.rawValue),
            "fixed": .bool(h.mode != .scrolls),
            "shrinks": .bool(shrinks),
            "logo": .string(h.isLogoShown ? src(h.logo) : ""),
            "logoAlt": .string(alt.isEmpty ? c.title : alt),
            "logoWidth": .bool(logoWidth > 0),
            "compactLogo": .string(compactLogo),
            // Nothing to show when the logo and the title are both off.
            "brandLeft": .bool(hasBrand && h.logoPosition == .left),
            "brandCenter": .bool(hasBrand && h.logoPosition == .center),
            "brandRight": .bool(hasBrand && h.logoPosition == .right),
            "brandStyle": .string(brandStyle),
            "showTitle": .bool(h.showTitle),
            "style": .string(style),
        ])
    }

    /// A unitless CSS number with up to 4 decimals, e.g. 0.5 or 0.6667.
    static func ratio(_ d: Double) -> String {
        var text = String(format: "%.4f", d)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}

extension SiteRenderer {
    /// Replaces each widget line in a page's HTML (the placeholders
    /// `markdownToHTML` left, not ones in code blocks) with its box. Each
    /// kind of box's styles go in once, before the first one.
    func insertWidgets(into html: String) -> String {
        guard html.contains("<!--cardstock:") else { return html }
        var html = html
        for widget in PageWidget.allCases where html.contains(widget.placeholder) {
            let box: String
            let style: String
            switch widget {
            case .newsletter: (box, style) = (newsletterHTML(), Self.newsletterStyle)
            case .search: (box, style) = (searchBoxHTML(), Self.searchBoxStyle)
            }
            var parts = html.components(separatedBy: widget.placeholder)
            if !box.isEmpty {
                parts[0] += style
            }
            html = parts.joined(separator: box)
        }
        return html
    }

    /// Kept for callers and tests from before search boxes.
    func insertNewsletter(into html: String) -> String { insertWidgets(into: html) }

    /// The newsletter box. Without embed code it's a note in the preview
    /// (drafts are only included there) and nothing on the published site.
    func newsletterHTML() -> String {
        let n = site.config.newsletter
        let embed: String
        if n.hasEmbed {
            embed = n.embed
        } else if includeDrafts {
            embed = #"<p class="newsletter-missing">Paste your newsletter service's embed code in Configuration → Mailing List, and its sign-up form shows here.</p>"#
        } else {
            return ""
        }
        var html = #"<section class="newsletter newsletter-\#(n.style.rawValue) newsletter-\#(n.alignment.rawValue)">"#
        let heading = n.heading.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = n.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !heading.isEmpty { html += "<h2>\(escapeHTML(heading))</h2>" }
        if !text.isEmpty { html += "<p>\(escapeHTML(text))</p>" }
        html += #"<div class="newsletter-embed">"# + embed + "</div></section>"
        return html
    }

    /// Styles for the box, using the theme's card settings so it matches.
    static let newsletterStyle = """
    <style>
    .newsletter { margin: 2rem 0; }
    .newsletter-card { padding: var(--card-padding, 1.25rem); border: var(--card-border, 1px solid var(--line)); border-radius: var(--card-radius, 10px); box-shadow: var(--card-shadow, none); background: var(--card); }
    .newsletter h2 { margin: 0 0 0.35rem; font-size: 1.3rem; }
    .newsletter > p { margin: 0 0 1rem; color: var(--muted); }
    .newsletter-center { text-align: center; }
    .newsletter-center .newsletter-embed { display: flex; flex-direction: column; align-items: center; }
    .newsletter-embed iframe { max-width: 100%; border: 0; }
    .newsletter-missing { padding: 1rem; border: 1px dashed var(--line); border-radius: var(--radius, 8px); color: var(--muted); font-size: 0.9rem; }
    </style>
    """
}

extension SiteRenderer {
    /// The search box pages show with a `<!-- search -->` line: a field
    /// that opens the Search page with the words typed. With search off,
    /// it's a note in the preview and nothing on the published site.
    func searchBoxHTML() -> String {
        let search = site.config.search
        guard search.enabled else {
            return includeDrafts
                ? #"<p class="newsletter-missing">Search is off. Turn it on in Configuration → Search and a search box shows here.</p>"#
                : ""
        }
        let placeholder = escapeHTML(search.shownPlaceholder)
        return #"<form class="search-box" action="/\#(ContentItem.searchSlug)/" method="get" role="search">"#
            + #"<input type="search" name="q" placeholder="\#(placeholder)" aria-label="\#(placeholder)">"#
            + #"<button class="button" type="submit">\#(escapeHTML(search.shownButtonLabel))</button></form>"#
    }

    static let searchBoxStyle = """
    <style>
    .search-box { display: flex; gap: 0.5rem; margin: 1.5rem 0; max-width: 32rem; }
    .search-box input { flex: 1; min-width: 0; padding: var(--button-pad-y, 0.5rem) 0.85rem; font: inherit; font-size: 1rem; color: var(--text); background: var(--card); border: 1px solid var(--line); border-radius: var(--button-radius, 6px); }
    .search-box input:focus { outline: 2px solid var(--accent); outline-offset: 1px; border-color: transparent; }
    .search-box button { cursor: pointer; font: inherit; font-family: var(--font-heading); font-size: 0.95rem; }
    .newsletter-missing { padding: 1rem; border: 1px dashed var(--line); border-radius: var(--radius, 8px); color: var(--muted); font-size: 0.9rem; }
    </style>
    """

    /// The pages search can find, as the JSON the Search page loads: each
    /// with `title`, `url`, `type`, `date` (posts), `summary`, `tags` and
    /// `text` (the start of its text, without formatting).
    func searchIndexJSON() -> String {
        let search = site.config.search
        let pages = site.items.filter { item in
            search.includes(item.kind) && !item.isFixedPage && !item.isLinkMenu
                && (includeDrafts || !item.isDraft)
        }
        let entries: [[String: Any]] = pages.map { item in
            var entry: [String: Any] = [
                "title": item.title,
                "url": item.path,
                "type": site.config.visitorTypeName(item.kind),
                "summary": item.frontMatter.string("summary") ?? "",
                // Tags, and the names of the categories it's in.
                "tags": item.tags + (item.kind.isItem ? item.categories.map { slug in
                    site.items.first { $0.slug == slug && $0.kind == .category(item.kind.collectionID!) }?.title ?? slug
                } : []),
                "text": Self.plainText(item.body, limit: 5000),
            ]
            if item.kind.isItem, site.collection(for: item.kind)?.dated == true, !item.date.isEmpty {
                entry["date"] = displayDate(item.date)
            }
            return entry
        }
        let data = (try? JSONSerialization.data(withJSONObject: entries, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// A page's Markdown as plain text: formatted, then without tags,
    /// comments or extra spaces, cut to about `limit` characters.
    static func plainText(_ markdown: String, limit: Int) -> String {
        var html = markdownToHTML(markdown)
        // Comments, scripts and block tags become spaces; inline tags (links,
        // bold, code) just go, so "a <b>word</b>," stays "a word,".
        for pattern in [#"<!--[\s\S]*?-->"#, #"<(script|style)[\s\S]*?</\1>"#,
                        #"</?(p|div|li|ul|ol|h[1-6]|br|hr|tr|td|th|table|thead|tbody|blockquote|pre|figure|figcaption|section)\b[^>]*>"#] {
            html = html.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        html = html.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        for (entity, char) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " "), ("&amp;", "&")] {
            html = html.replacingOccurrences(of: entity, with: char)
        }
        let text = html.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard text.count > limit else { return text }
        let cut = text.prefix(limit)
        return String(cut[..<(cut.lastIndex(of: " ") ?? cut.endIndex)])
    }
}

extension SiteRenderer {
    /// Classes in a page's HTML that need `collectionStyle`.
    static let collectionMarkers = [#"class="collection-"#, #"class="project-grid collection-"#, #"class="pager""#,
                                    #"class="video-embed""#, #"class="category-links""#, #"class="tag-cloud""#]

    /// Styles for collection lists, galleries, category links, the pager,
    /// videos and the tag list, using the theme's variables.
    static let collectionStyle = """
    <style>
    .collection-grid { display: grid; grid-template-columns: repeat(var(--cols, 3), minmax(0, 1fr)); gap: 1.25rem; margin: 2rem 0; }
    .collection-grid .project-card img { display: block; width: 100%; aspect-ratio: 4 / 3; object-fit: cover; }
    .collection-grid .project-card time { display: block; margin: 0 0 0.35rem; }
    .collection-gallery { gap: 0.9rem; }
    .gallery-item { display: block; color: var(--text); text-decoration: none; }
    .gallery-item img, .gallery-blank { display: block; width: 100%; aspect-ratio: 1; object-fit: cover; border-radius: var(--image-radius, 0); transition: opacity 0.2s; }
    .gallery-blank { background: var(--card); border: 1px solid var(--line); }
    .gallery-item:hover img { opacity: 0.85; }
    .gallery-item > span:not(.gallery-blank) { display: block; margin-top: 0.45rem; font-family: var(--font-heading); font-size: 0.95rem; font-weight: 600; }
    .gallery-item:hover > span:not(.gallery-blank) { color: var(--accent); }
    .gallery-item time { display: block; font-size: 0.8rem; }
    @media (max-width: 760px) { .collection-grid { grid-template-columns: repeat(min(var(--cols, 3), 2), minmax(0, 1fr)); } }
    @media (max-width: 460px) { .collection-grid:not(.collection-gallery) { grid-template-columns: 1fr; } }
    .post-list .price { margin: 0.25rem 0 0; }
    .tag-list .meta { display: block; }
    .category-links, .tag-cloud { display: flex; flex-wrap: wrap; gap: 0.5rem; list-style: none; padding: 0; margin: 1.25rem 0 0; }
    .category-links a, .tag-cloud a { display: inline-block; padding: 0.3rem 0.8rem; border: 1px solid var(--line); border-radius: 999px; font-family: var(--font-heading); font-size: 0.85rem; color: var(--text); text-decoration: none; }
    .category-links a:hover, .tag-cloud a:hover { border-color: var(--accent); color: var(--accent); }
    .category-links a[aria-current] { background: var(--accent); border-color: var(--accent); color: var(--bg); }
    .tag-cloud { margin: 2rem 0; }
    .tag-heading { font-size: 1.1rem; margin: 2.5rem 0 0; }
    .tag-cloud small { color: var(--muted); margin-left: 0.3em; }
    .video-embed { position: relative; aspect-ratio: 16 / 9; margin: 1.5rem 0; border-radius: var(--cover-radius, 8px); overflow: hidden; background: #000; }
    .video-embed iframe, .video-embed video { position: absolute; inset: 0; width: 100%; height: 100%; border: 0; }
    .video-link { margin: 1.5rem 0; }
    .pager { display: grid; grid-template-columns: 1fr auto 1fr; align-items: start; gap: 1rem; margin: 3rem 0 0; padding-top: 1.25rem; border-top: 1px solid var(--line); font-family: var(--font-heading); font-size: 0.95rem; }
    .pager a { text-decoration: none; }
    .pager small { display: block; color: var(--muted); font-size: 0.78rem; text-transform: uppercase; letter-spacing: 0.06em; }
    .pager .all { align-self: center; font-size: 0.85rem; }
    .pager .next { text-align: right; }
    @media (max-width: 560px) { .pager { grid-template-columns: 1fr 1fr; } .pager .all { grid-column: 1 / -1; grid-row: 2; text-align: center; } }
    </style>
    """

    /// YouTube, YouTube Shorts and youtu.be links: the video's id.
    static func youTubeID(_ link: String) -> String? {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespaces)),
              let host = url.host()?.lowercased() else { return nil }
        let parts = url.path().split(separator: "/").map(String.init)
        var id: String?
        if host.hasSuffix("youtu.be") {
            id = parts.first
        } else if host.hasSuffix("youtube.com") || host.hasSuffix("youtube-nocookie.com") {
            if let first = parts.first, ["embed", "shorts", "live", "v"].contains(first), parts.count > 1 {
                id = parts[1]
            } else {
                id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "v" }?.value
            }
        }
        guard let id, !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        return id
    }

    /// A video link as a player: YouTube and Vimeo links become their
    /// players, video files (.mp4, .webm, .mov, .m4v) a `<video>`, and
    /// anything else a plain link. Empty for no link.
    static func videoEmbedHTML(_ link: String) -> String {
        let link = link.trimmingCharacters(in: .whitespaces)
        guard !link.isEmpty else { return "" }
        let frame = { (src: String) in
            #"<div class="video-embed"><iframe src="\#(escapeHTML(src))" title="Video" loading="lazy" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen></iframe></div>"#
        }
        if let id = youTubeID(link) { return frame("https://www.youtube-nocookie.com/embed/\(id)") }
        if let url = URL(string: link), url.host()?.lowercased().hasSuffix("vimeo.com") == true,
           let id = url.path().split(separator: "/").last(where: { $0.allSatisfy(\.isNumber) }) {
            return frame("https://player.vimeo.com/video/\(id)")
        }
        let ext = (link.split(separator: "?").first.map(String.init) ?? link).split(separator: ".").last?.lowercased() ?? ""
        if ["mp4", "webm", "mov", "m4v"].contains(ext) {
            return #"<div class="video-embed"><video src="\#(escapeHTML(link))" controls playsinline preload="metadata"></video></div>"#
        }
        return #"<p class="video-link"><a href="\#(escapeHTML(link))">Watch the video</a></p>"#
    }

    /// A thumbnail for a YouTube link, for lists.
    static func videoThumbnail(_ link: String) -> String? {
        youTubeID(link).map { "https://i.ytimg.com/vi/\($0)/hqdefault.jpg" }
    }
}
