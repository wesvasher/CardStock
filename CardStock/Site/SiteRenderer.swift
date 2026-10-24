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
    static let templateNames = ["base", "home", "post", "page"]
    /// Templates added with page types. A theme without them uses
    /// CardStock's built-in versions.
    static let newerTemplateNames = ["blog-category", "product", "shop-category", "shop"]
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
        if !published(.product).isEmpty { paths.append("/shop/") }
        for kind in ContentKind.allCases where kind != .links {
            // Link menus only appear inside the footer; the Template page
            // only in the preview.
            paths += published(kind)
                .filter { !$0.isHome && !$0.isTemplatePage && !($0.isSearchPage && !site.config.search.enabled) }
                .map(\.path)
        }
        if site.config.search.enabled { paths.append(Self.searchIndexPath) }
        return paths
    }

    /// Renders one path, or returns nil when nothing lives there.
    func render(path: String) -> String? {
        switch path {
        case "/", "/index.html":
            return renderHome()
        case "/shop/", "/shop/index.html":
            return renderList("shop", key: "products", items: published(.product), path: "/shop/", title: "Shop")
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
            let candidates = ContentKind.allCases.flatMap(published)
            guard let item = candidates.first(where: { $0.path == normalized }) else { return nil }
            return render(item)
        }
    }

    func render(_ item: ContentItem) -> String {
        if item.isHome { return renderHome(item) }
        let value = itemValue(item)
        let key: String
        let template: String
        switch item.kind {
        case .post: (key, template) = ("post", "post")
        case .page where item.isTemplatePage: (key, template) = ("page", Self.templatePageTemplate)
        case .page where item.isSearchPage: (key, template) = ("page", Self.searchTemplate)
        case .page, .links: (key, template) = ("page", "page")
        case .blogCategory: (key, template) = ("page", "blog-category")
        case .product: (key, template) = ("product", "product")
        case .shopCategory: (key, template) = ("page", "shop-category")
        }
        var context = globals(path: item.path, title: item.title, description: item.frontMatter.string("summary"))
        if key == "page", case .dict(var page) = value, case .dict(let meta)? = context["page"] {
            page.merge(meta) { itemField, _ in itemField }
            context["page"] = .dict(page)
        } else {
            context[key] = value
        }
        if item.isSearchPage {
            let search = site.config.search
            context["search"] = .dict([
                "index": .string(Self.searchIndexPath),
                "placeholder": .string(search.shownPlaceholder),
                "buttonLabel": .string(search.shownButtonLabel),
            ])
        }
        // Category pages list their posts or products.
        if let member = item.kind.memberKind {
            let listed = members(of: item)
            context[member == .post ? "posts" : "products"] = .list(listed.map(itemValue))
        }
        if let layout = layout(for: item) {
            return renderLayout(item, layout, context: context)
        }
        return wrap(templates[template]!.render(.dict(context)), context: context)
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
        context["posts"] = .list(published(.post).map(itemValue))
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
        context["recentPosts"] = .list(published(.post).prefix(5).map(itemValue))
        context["blogCategories"] = .list(published(.blogCategory).map(itemValue))
        return wrap(template.render(.dict(context)), context: context)
    }

    /// Shown above the text: a post's date, categories and tags, or a
    /// product's price.
    private func metaHTML(_ item: ContentItem) -> String {
        switch item.kind {
        case .post:
            var html = #"<p class="meta"><time datetime="\#(escapeHTML(item.date))">\#(escapeHTML(displayDate(item.date)))</time>"#
            let categories = categoryLinksHTML(item)
            if !categories.isEmpty { html += " · " + categories }
            let tags = item.frontMatter.list("tags")
            if !tags.isEmpty { html += " · " + tags.map { #"<span class="tag">\#(escapeHTML($0))</span>"# }.joined() }
            return html + "</p>"
        case .product:
            let price = item.frontMatter.string("price") ?? ""
            return price.isEmpty ? "" : #"<p class="price">\#(escapeHTML(price))</p>"#
        default:
            return ""
        }
    }

    /// Shown below the text: a product's Buy button and categories.
    private func actionsHTML(_ item: ContentItem) -> String {
        guard item.kind == .product else { return "" }
        var html = ""
        let buy = item.frontMatter.string("buy") ?? ""
        if !buy.isEmpty {
            let label = item.frontMatter.string("buyLabel").flatMap { $0.isEmpty ? nil : $0 } ?? "Buy Now"
            html += #"<p><a class="button buy" href="\#(escapeHTML(buy))" target="_blank" rel="noopener">\#(escapeHTML(label))</a></p>"#
        }
        let categories = categoryLinksHTML(item)
        if !categories.isEmpty { html += #"<p class="meta">In \#(categories)</p>"# }
        return html
    }

    private func categoryLinksHTML(_ item: ContentItem) -> String {
        guard let kind = item.kind.categoryKind else { return "" }
        let categories = published(kind)
        return item.categories.compactMap { slug in
            categories.first { $0.slug == slug }.map {
                #"<a class="category" href="\#(escapeHTML($0.path))">\#(escapeHTML($0.title))</a>"#
            }
        }.joined()
    }

    /// A category's posts or products, or Home's posts.
    private func listingHTML(_ item: ContentItem) -> String {
        let memberKind: ContentKind? = item.isHome ? .post : item.kind.memberKind
        guard let memberKind else { return "" }
        let members = item.isHome ? published(.post) : self.members(of: item)
        if memberKind == .post {
            guard !members.isEmpty else { return #"<p class="empty">No posts yet.</p>"# }
            let rows = members.map { post in
                var row = #"<li><a href="\#(escapeHTML(post.path))">\#(escapeHTML(post.title))</a> <time datetime="\#(escapeHTML(post.date))">\#(escapeHTML(displayDate(post.date)))</time>"#
                let summary = post.frontMatter.string("summary") ?? ""
                if !summary.isEmpty { row += "<p>\(escapeHTML(summary))</p>" }
                return row + "</li>"
            }
            return #"<ul class="post-list">"# + rows.joined() + "</ul>"
        }
        guard !members.isEmpty else { return #"<p class="empty">Nothing here yet.</p>"# }
        let cards = members.map { product in
            var card = #"<a class="project-card" href="\#(escapeHTML(product.path))">"#
            let cover = product.frontMatter.string("cover") ?? ""
            if !cover.isEmpty { card += #"<img src="\#(escapeHTML(cover))" alt="">"# }
            card += "<h2>\(escapeHTML(product.title))</h2>"
            let price = product.frontMatter.string("price") ?? ""
            if !price.isEmpty { card += #"<p class="price">\#(escapeHTML(price))</p>"# }
            let summary = product.frontMatter.string("summary") ?? ""
            if !summary.isEmpty { card += "<p>\(escapeHTML(summary))</p>" }
            return card + "</a>"
        }
        return #"<div class="project-grid">"# + cards.joined() + "</div>"
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

    private func renderList(_ template: String, key: String, items: [ContentItem], path: String, title: String) -> String {
        var context = globals(path: path, title: title, description: site.config.description)
        context[key] = .list(items.map(itemValue))
        return wrap(templates[template]!.render(.dict(context)), context: context)
    }

    private func wrap(_ body: String, context: [String: TemplateValue]) -> String {
        var context = context
        context["body"] = .string(insertWidgets(into: body))
        let html = Lightbox.inject(into: templates["base"]!.render(.dict(context)))
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
        if item.kind.categoryKind != nil {
            // The categories it's in, as links (unknown or draft ones left out).
            let categories = published(item.kind.categoryKind!)
            dict["categoryLinks"] = .list(item.categories.compactMap { slug in
                categories.first { $0.slug == slug }.map { .dict(["title": .string($0.title), "url": .string($0.path)]) }
            })
        }
        if item.kind == .product {
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
        for post in published(.post).prefix(20) {
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
    /// The published posts or products in a category page, in site order
    /// (posts newest first).
    func members(of category: ContentItem) -> [ContentItem] {
        guard let member = category.kind.memberKind else { return [] }
        return site.items(member)
            .filter { includeDrafts || !$0.isDraft }
            .filter { $0.categories.contains(category.slug) }
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
                "type": Self.visitorTypeName(item.kind),
                "summary": item.frontMatter.string("summary") ?? "",
                // Tags, and the names of the categories it's in.
                "tags": item.frontMatter.list("tags") + item.categories.map { slug in
                    site.items.first { $0.slug == slug && $0.kind == item.kind.categoryKind }?.title ?? slug
                },
                "text": Self.plainText(item.body, limit: 5000),
            ]
            if item.kind == .post, !item.date.isEmpty { entry["date"] = displayDate(item.date) }
            return entry
        }
        let data = (try? JSONSerialization.data(withJSONObject: entries, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// What a page is, in words for site visitors (shown in search results).
    static func visitorTypeName(_ kind: ContentKind) -> String {
        switch kind {
        case .page, .links: "Page"
        case .post: "Post"
        case .product: "Product"
        case .blogCategory, .shopCategory: "Category"
        }
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
