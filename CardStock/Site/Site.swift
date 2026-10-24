import Foundation

/// Settings from `site.json`.
struct SiteConfig: Codable, Equatable, Sendable {
    struct NavLink: Codable, Equatable, Sendable, Identifiable {
        var title: String
        var url: String
        /// Top bar only: show the link as a button (Configuration → Top
        /// Navigation Bar → Button Style).
        var button = false
        /// Top bar only: a `NavIcon` id shown with the text. With no text,
        /// the link is just the icon.
        var icon = ""
        var id: String { url + title }

        private enum CodingKeys: String, CodingKey { case title, url, button, icon }

        init(title: String, url: String, button: Bool = false, icon: String = "") {
            self.title = title
            self.url = url
            self.button = button
            self.icon = icon
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
            button = try c.decodeIfPresent(Bool.self, forKey: .button) ?? false
            icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? ""
        }

        /// Leaves out `button` and `icon` when unset, so plain links stay
        /// `{ "title", "url" }` in site.json.
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(title, forKey: .title)
            try c.encode(url, forKey: .url)
            if button { try c.encode(true, forKey: .button) }
            if !icon.isEmpty { try c.encode(icon, forKey: .icon) }
        }
    }

    var title = "My Site"
    var description = ""
    var author = ""
    var url = ""
    var language = "en"
    /// The top bar's right-hand group of links (`header.showRightLinks`
    /// turns it off). Kept as `nav` so themes made before link groups still
    /// show the menu.
    var nav: [NavLink] = []
    var header = Header()
    var footer = Footer()
    var newsletter = Newsletter()
    var search = Search()
    /// How pages are addressed. 1: sites from before 0.6 (static pages at
    /// /<slug>/, posts at /posts/<slug>/); `SiteMigration.moveAddresses`
    /// moves them to 2: /pages/<slug>/ and /<collection>/pages/<slug>/.
    var addressVersion = SiteConfig.currentAddressVersion
    static let currentAddressVersion = 2
    /// Tag pages and tag descriptions (Configuration → Tags).
    var tags = TagSettings()
    /// Your own folders: short addresses like /subscribe/ that show a page
    /// (Configuration → Folders).
    var folders: [Folder] = []
    /// nil when site.json has no `collections` yet; `Site.load` fills in
    /// the defaults so they're saved with the next change.
    var storedCollections: [ContentCollection]?

    /// The site's collections, such as the blog and the shop, in menu order.
    var collections: [ContentCollection] {
        get { storedCollections ?? [ContentCollection(preset: .blog, id: ContentCollection.blogID)] }
        set { storedCollections = newValue }
    }

    private enum CodingKeys: String, CodingKey {
        case title, description, author, url, language, nav, header, footer, newsletter, search, tags, addressVersion, folders
        case storedCollections = "collections"
    }

    /// Site search: the Search page (pages/search.md at /pages/search/), the
    /// index it searches (/search.json) and the search box pages can show
    /// with a `<!-- search -->` line. Edited in Configuration → Search.
    struct Search: Codable, Equatable, Sendable {
        /// Off leaves out the Search page, the index and every search box.
        var enabled = true
        /// Page types whose pages can be found, as `ContentKind` raw values.
        var kinds: [String] = [ContentKind.page, .post, .product].map(\.rawValue)
        var placeholder = "Search"
        var buttonLabel = "Search"

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Search()
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
            kinds = try c.decodeIfPresent([String].self, forKey: .kinds) ?? d.kinds
            placeholder = try c.decodeIfPresent(String.self, forKey: .placeholder) ?? d.placeholder
            buttonLabel = try c.decodeIfPresent(String.self, forKey: .buttonLabel) ?? d.buttonLabel
        }

        /// A collection's main page is found when its items are.
        func includes(_ kind: ContentKind) -> Bool {
            if case .main(let c) = kind { return kinds.contains(ContentCollection.itemType(c)) }
            return kinds.contains(kind.rawValue)
        }

        var shownPlaceholder: String {
            let t = placeholder.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? "Search" : t
        }

        var shownButtonLabel: String {
            let t = buttonLabel.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? "Search" : t
        }
    }

    /// A sign-up box for a newsletter, placed in pages with a
    /// `<!-- newsletter -->` line. The form itself is embed code (an iframe
    /// or a script and form) from a newsletter service. Edited in
    /// Configuration → Mailing List.
    struct Newsletter: Codable, Equatable, Sendable {
        /// The line that marks where the box goes in a page's Markdown.
        static var marker: String { PageWidget.newsletter.marker }

        enum Style: String, Codable, CaseIterable, Sendable {
            /// In a card, like product cards.
            case card
            /// Straight on the page.
            case plain
        }

        enum Alignment: String, Codable, CaseIterable, Sendable {
            case left, center
        }

        var heading = "Subscribe to the newsletter"
        var text = "Get new posts by email. Unsubscribe any time."
        /// The service's embed code, used as is.
        var embed = ""
        var style = Style.card
        var alignment = Alignment.left

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Newsletter()
            heading = try c.decodeIfPresent(String.self, forKey: .heading) ?? d.heading
            text = try c.decodeIfPresent(String.self, forKey: .text) ?? d.text
            embed = try c.decodeIfPresent(String.self, forKey: .embed) ?? ""
            style = (try? c.decodeIfPresent(Style.self, forKey: .style)) ?? d.style
            alignment = (try? c.decodeIfPresent(Alignment.self, forKey: .alignment)) ?? d.alignment
        }

        var hasEmbed: Bool { !embed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        /// True when a page's Markdown has a newsletter line (outside code blocks).
        static func isUsed(in markdown: String) -> Bool { PageWidget.newsletter.isUsed(in: markdown) }

        /// What newsletter lines become before Markdown formatting.
        static var placeholder: String { PageWidget.newsletter.placeholder }

        /// Turns widget lines outside code blocks into placeholders.
        static func markPlaces(in markdown: String) -> String { PageWidget.markPlaces(in: markdown) }
    }

    /// The top navigation bar on every page: the site's logo or title and
    /// the menu. Edited on the Theming page.
    struct Header: Codable, Equatable, Sendable {
        enum Mode: String, Codable, CaseIterable, Sendable {
            /// Part of the page: scrolls away (the original header).
            case scrolls
            /// Stays at the top, the same size, with the page blurred behind it.
            case fixed
            /// Stays at the top and shrinks as the page scrolls, switching
            /// to the compact logo.
            case shrinking
        }

        /// Where the logo and site title sit in the bar.
        enum Position: String, Codable, CaseIterable, Sendable {
            case left, center, right
        }

        /// Space around the logo and title, in pixels.
        struct Padding: Codable, Equatable, Sendable {
            var top = 0
            var right = 0
            var bottom = 0
            var left = 0

            var isZero: Bool { top == 0 && right == 0 && bottom == 0 && left == 0 }
        }

        var mode = Mode.scrolls
        /// Logo image address, e.g. /media/files/logo.svg. Empty shows the site title.
        var logo = ""
        /// Off hides the logo (the site title shows instead) but keeps its settings.
        var showLogo = true
        var logoHeight = 40
        /// Logo width in pixels. 0 follows the image's shape (always for SVG).
        var logoWidth = 0
        /// Text for screen readers. Empty uses the site title.
        var logoAlt = ""
        var logoPosition = Position.left
        var logoPadding = Padding()
        /// Shown when a shrinking bar is small. Empty keeps the main logo.
        var compactLogo = ""
        var compactLogoHeight = 28
        /// Show the site title next to the logo.
        var showTitle = true
        /// Bar height for fixed bars, and shrinking bars before scrolling.
        var height = 88
        /// A shrinking bar's height once the page has scrolled.
        var compactHeight = 56

        /// Link groups. The right group's links are `SiteConfig.nav`.
        var showLeftLinks = false
        var leftLinks: [NavLink] = []
        var showCenterLinks = false
        var centerLinks: [NavLink] = []
        var showRightLinks = true
        /// On phones, the links fold into a menu button that opens them in a
        /// full-screen overlay.
        var mobileMenu = true

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Header()
            mode = (try? c.decodeIfPresent(Mode.self, forKey: .mode)) ?? d.mode
            logo = try c.decodeIfPresent(String.self, forKey: .logo) ?? ""
            logoHeight = try c.decodeIfPresent(Int.self, forKey: .logoHeight) ?? d.logoHeight
            compactLogo = try c.decodeIfPresent(String.self, forKey: .compactLogo) ?? ""
            compactLogoHeight = try c.decodeIfPresent(Int.self, forKey: .compactLogoHeight) ?? d.compactLogoHeight
            showTitle = try c.decodeIfPresent(Bool.self, forKey: .showTitle) ?? d.showTitle
            height = try c.decodeIfPresent(Int.self, forKey: .height) ?? d.height
            compactHeight = try c.decodeIfPresent(Int.self, forKey: .compactHeight) ?? d.compactHeight
            logoWidth = try c.decodeIfPresent(Int.self, forKey: .logoWidth) ?? 0
            showLogo = try c.decodeIfPresent(Bool.self, forKey: .showLogo) ?? d.showLogo
            logoAlt = try c.decodeIfPresent(String.self, forKey: .logoAlt) ?? ""
            logoPosition = (try? c.decodeIfPresent(Position.self, forKey: .logoPosition)) ?? d.logoPosition
            logoPadding = (try? c.decodeIfPresent(Padding.self, forKey: .logoPadding)) ?? d.logoPadding
            showLeftLinks = try c.decodeIfPresent(Bool.self, forKey: .showLeftLinks) ?? d.showLeftLinks
            leftLinks = try c.decodeIfPresent([NavLink].self, forKey: .leftLinks) ?? []
            showCenterLinks = try c.decodeIfPresent(Bool.self, forKey: .showCenterLinks) ?? d.showCenterLinks
            centerLinks = try c.decodeIfPresent([NavLink].self, forKey: .centerLinks) ?? []
            showRightLinks = try c.decodeIfPresent(Bool.self, forKey: .showRightLinks) ?? d.showRightLinks
            mobileMenu = try c.decodeIfPresent(Bool.self, forKey: .mobileMenu) ?? d.mobileMenu
        }

        var hasLogo: Bool { !logo.trimmingCharacters(in: .whitespaces).isEmpty }
        /// A logo is chosen and turned on.
        var isLogoShown: Bool { showLogo && hasLogo }
    }

    /// The bar at the bottom of every page. The defaults match the footer
    /// sites had before these settings existed.
    struct Footer: Codable, Equatable, Sendable {
        var enabled = true
        var showCopyright = true
        /// Name after "© <year>". Empty uses the author, then the site title.
        var copyrightName = ""
        var links: [NavLink] = []
        var showFeed = true
        var logo = Logo()
        /// Drop-down menus next to the RSS button, each filled from a link menu page.
        var menus: [Menu] = []
        /// An optional "Designed with CardStock" link to CardStock's repo.
        var attribution = Attribution()

        struct Attribution: Codable, Equatable, Sendable {
            static let url = "https://github.com/wesvasher/CardStock"
            static let defaultText = "Designed with CardStock"

            var enabled = false
            /// The link's text. Empty uses `defaultText`.
            var text = ""

            init() {}

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
                text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
            }

            var shownText: String {
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty ? Self.defaultText : trimmed
            }
        }

        /// A button in the footer that opens a list of links.
        struct Menu: Codable, Equatable, Sendable {
            /// The button's text.
            var title: String
            /// Slug of the link menu page, e.g. "social" for pages/social.md.
            var page: String
        }

        /// An image in the footer, such as a logo, at a size you set.
        struct Logo: Codable, Equatable, Sendable {
            enum Placement: String, Codable, CaseIterable, Sendable {
                /// In the footer's row, before the copyright.
                case left
                /// On its own row under the footer's row, centered.
                case below
            }

            /// Address of the image, e.g. /media/files/logo.png. Empty means no logo.
            var image = ""
            /// Text for screen readers. Empty uses the site title.
            var alt = ""
            /// Size in pixels on the page. 0 leaves that side to the browser.
            var width = 0
            var height = 0
            var placement = Placement.left
            /// Space above and below the logo when it's on its own row.
            var paddingTop = 16
            var paddingBottom = 16

            init() {}

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                let d = Logo()
                image = try c.decodeIfPresent(String.self, forKey: .image) ?? ""
                alt = try c.decodeIfPresent(String.self, forKey: .alt) ?? ""
                width = try c.decodeIfPresent(Int.self, forKey: .width) ?? 0
                height = try c.decodeIfPresent(Int.self, forKey: .height) ?? 0
                placement = (try? c.decodeIfPresent(Placement.self, forKey: .placement)) ?? d.placement
                paddingTop = try c.decodeIfPresent(Int.self, forKey: .paddingTop) ?? d.paddingTop
                paddingBottom = try c.decodeIfPresent(Int.self, forKey: .paddingBottom) ?? d.paddingBottom
            }

            var hasImage: Bool { !image.trimmingCharacters(in: .whitespaces).isEmpty }
        }

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Footer()
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
            showCopyright = try c.decodeIfPresent(Bool.self, forKey: .showCopyright) ?? d.showCopyright
            copyrightName = try c.decodeIfPresent(String.self, forKey: .copyrightName) ?? ""
            links = try c.decodeIfPresent([NavLink].self, forKey: .links) ?? []
            showFeed = try c.decodeIfPresent(Bool.self, forKey: .showFeed) ?? d.showFeed
            logo = try c.decodeIfPresent(Logo.self, forKey: .logo) ?? Logo()
            menus = try c.decodeIfPresent([Menu].self, forKey: .menus) ?? []
            attribution = try c.decodeIfPresent(Attribution.self, forKey: .attribution) ?? Attribution()
        }
    }

    /// The copyright line, e.g. "© 2026 Ann Lee", or empty when it's off.
    func copyrightText(year: Int = Calendar.current.component(.year, from: .now)) -> String {
        guard footer.showCopyright else { return "" }
        let name = [footer.copyrightName, author, title]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        return "© \(year) \(name)".trimmingCharacters(in: .whitespaces)
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? title
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? language
        nav = try c.decodeIfPresent([NavLink].self, forKey: .nav) ?? []
        header = try c.decodeIfPresent(Header.self, forKey: .header) ?? Header()
        footer = try c.decodeIfPresent(Footer.self, forKey: .footer) ?? Footer()
        newsletter = try c.decodeIfPresent(Newsletter.self, forKey: .newsletter) ?? Newsletter()
        search = try c.decodeIfPresent(Search.self, forKey: .search) ?? Search()
        tags = try c.decodeIfPresent(TagSettings.self, forKey: .tags) ?? TagSettings()
        addressVersion = try c.decodeIfPresent(Int.self, forKey: .addressVersion) ?? 1
        folders = try c.decodeIfPresent([Folder].self, forKey: .folders) ?? []
        storedCollections = try c.decodeIfPresent([ContentCollection].self, forKey: .storedCollections)
    }

    /// Every link shown in the top bar: the left, center and right groups
    /// that are turned on.
    var menuLinks: [NavLink] {
        (header.showLeftLinks ? header.leftLinks : [])
            + (header.showCenterLinks ? header.centerLinks : [])
            + (header.showRightLinks ? nav : [])
    }

    /// `url` without a trailing slash.
    var baseURL: String {
        url.hasSuffix("/") ? String(url.dropLast()) : url
    }
}

/// One Markdown file in `pages/`.
struct ContentItem: Identifiable, Equatable, Sendable {
    var slug: String
    var fileURL: URL
    var frontMatter: FrontMatter
    var body: String

    /// The page's type, from its `type:` front matter. Home and the 404
    /// page are always static pages.
    var kind: ContentKind {
        get {
            if slug == Self.homeSlug || slug == Self.notFoundSlug || slug == Self.templateSlug || slug == Self.searchSlug { return .page }
            return frontMatter.string("type").flatMap { ContentKind(rawValue: $0, slug: slug) } ?? .page
        }
        set {
            frontMatter["type"] = newValue == .page ? nil : .string(newValue.rawValue)
            if newValue == .post && date.isEmpty {
                date = ISO8601DateFormatter.string(from: .now, timeZone: .current, formatOptions: [.withFullDate])
            }
        }
    }

    /// Slugs of the category pages this item is in.
    var categories: [String] {
        get { frontMatter.list("categories") }
        set { frontMatter["categories"] = newValue.isEmpty ? nil : .list(newValue) }
    }

    var id: URL { fileURL }

    var title: String {
        get { frontMatter.string("title") ?? slug }
        set { frontMatter.setString("title", newValue) }
    }

    /// `YYYY-MM-DD`, or empty.
    var date: String {
        get { frontMatter.string("date") ?? "" }
        set { frontMatter.setString("date", newValue) }
    }

    /// The page layout's id (a file in theme/layouts), or empty for the
    /// type's standard layout.
    var layout: String {
        get { frontMatter.string("layout") ?? "" }
        set { frontMatter.setString("layout", newValue) }
    }

    var isDraft: Bool {
        get { frontMatter.bool("draft") }
        set { frontMatter["draft"] = newValue ? .bool(true) : nil }
    }

    var path: String { kind.path(for: slug) }

    /// `pages/index.md` is the site's Home page.
    static let homeSlug = "index"
    var isHome: Bool { slug == Self.homeSlug }

    static let notFoundSlug = "404"
    /// The "page not found" page visitors see for a broken link.
    var isNotFoundPage: Bool { slug == Self.notFoundSlug }
    static let templateSlug = "template"
    /// The Template page: every part of the style on one page, shown in the
    /// preview with theme/template.html. Never published.
    var isTemplatePage: Bool { slug == Self.templateSlug }
    /// Home, 404 and Template: every site has them and their type is fixed.
    /// The Search page (pages/search.md at /pages/search/): a search field and its
    /// results, with the page's own text above. Can't be deleted.
    static let searchSlug = "search"
    var isSearchPage: Bool { slug == Self.searchSlug }
    /// The Search page's address.
    static var searchPath: String { ContentKind.page.path(for: searchSlug) }

    var isFixedPage: Bool { isHome || isNotFoundPage || isTemplatePage || isSearchPage }
    /// A page of links for a footer drop-down menu (`type: links`). It
    /// isn't published at its own address.
    var isLinkMenu: Bool { kind == .links }

    /// Pages every site needs, which can't be deleted.
    /// Collection main pages go when their collection is removed.
    var canBeDeleted: Bool { !isFixedPage && !kind.isMain }

    var fileText: String { FrontMatter.serialize(frontMatter, body: body) }

    init(fileURL: URL, text: String) {
        self.fileURL = fileURL
        self.slug = fileURL.deletingPathExtension().lastPathComponent
        (frontMatter, body) = FrontMatter.parse(text)
    }
}

/// A site folder loaded into memory.
struct Site: Sendable {
    var root: URL
    var config: SiteConfig
    var items: [ContentItem]
    /// Theming choices, or nil when the site hasn't used the Theming panel.
    var theme: ThemeSettings?
    /// Web fonts added to this site, from theme/fonts.json. They appear in
    /// the font menus whatever style is in use.
    var webFonts: [ThemeSettings.CustomFont] = []
    /// Page layouts from theme/layouts (or the built-in ones).
    var layouts: [PageLayout] = []
    /// Tags on files in media/ (media.json).
    var mediaTags = MediaTags()

    static let configFile = "site.json"
    /// Slugs a static page can't use, because other addresses start with them.
    static let reservedSlugs: Set<String> = ["pages", "links", "media", "assets", "feed.xml", "tags"]
    /// Names new pages can't take: reserved ones plus Home's and Template's.
    static let unavailablePageSlugs = reservedSlugs.union([ContentItem.homeSlug, ContentItem.templateSlug, ContentItem.searchSlug])

    /// Names new pages can't take in this site: the fixed ones, and each
    /// collection's address folders.
    var unavailableSlugs: Set<String> {
        Site.unavailablePageSlugs.union(config.collections.map(\.id))
    }

    static func isSite(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appending(path: configFile).path)
    }

    static func load(from root: URL) throws -> Site {
        let configURL = root.appending(path: configFile)
        let data: Data
        do {
            data = try Data(contentsOf: configURL)
        } catch {
            throw SiteError("“\(root.lastPathComponent)” isn't a CardStock site. It has no site.json.")
        }
        var config: SiteConfig
        do {
            config = try JSONDecoder().decode(SiteConfig.self, from: data)
        } catch {
            throw SiteError("site.json couldn't be read: \(error.localizedDescription)")
        }

        let items = try loadItems(root: root)
        if config.storedCollections == nil {
            config.collections = ContentCollection.defaults(for: items)
        }
        return Site(root: root, config: config, items: sorted(items), theme: ThemeSettings.load(from: root),
                    webFonts: loadWebFonts(from: root), layouts: PageLayout.load(root: root),
                    mediaTags: MediaTags.load(from: root))
    }

    static func loadItems(root: URL) throws -> [ContentItem] {
        let folder = root.appending(path: ContentKind.folder)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return try files
            .filter { $0.pathExtension.lowercased() == "md" }
            .map { ContentItem(fileURL: $0, text: try String(contentsOf: $0, encoding: .utf8)) }
    }

    /// Newest first for dated items, then by title.
    static func sorted(_ items: [ContentItem]) -> [ContentItem] {
        items.sorted { a, b in
            if a.date != b.date { return a.date > b.date }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    /// Items of one kind. Pages start with Home.
    func items(_ kind: ContentKind) -> [ContentItem] {
        let list = items.filter { $0.kind == kind }
        guard kind == .page else { return list }
        return list.filter(\.isHome) + list.filter { !$0.isHome }
    }

    var home: ContentItem? { items.first(where: \.isHome) }

    /// Adds the Template page (pages/template.md and theme/template.html) to
    /// sites made before it existed. Returns true if anything was added.
    @discardableResult
    static func ensureTemplatePage(in root: URL) throws -> Bool {
        let fm = FileManager.default
        var added = false
        let template = root.appending(path: "theme/\(SiteRenderer.templatePageTemplate).html")
        let early = root.appending(path: "theme/theme.html")  // its name in development builds
        if !fm.fileExists(atPath: template.path) {
            try fm.createDirectory(at: template.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: early.path) {
                try fm.moveItem(at: early, to: template)
            } else if let source = SiteRenderer.builtInTemplate(SiteRenderer.templatePageTemplate) {
                try source.write(to: template, atomically: true, encoding: .utf8)
                added = true
            }
        }
        let page = root.appending(path: "pages/\(ContentItem.templateSlug).md")
        if !fm.fileExists(atPath: page.path),
           let starter = Bundle.main.url(forResource: "StarterSite", withExtension: nil)?
               .appending(path: "pages/\(ContentItem.templateSlug).md") {
            try fm.createDirectory(at: page.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: starter, to: page)
            added = true
        }
        return added
    }

    /// Adds the Search page (pages/search.md) and its template
    /// (theme/search.html) to sites made before search existed. Returns
    /// true if anything was added.
    @discardableResult
    static func ensureSearchPage(in root: URL) throws -> Bool {
        let fm = FileManager.default
        var added = false
        let template = root.appending(path: "theme/\(SiteRenderer.searchTemplate).html")
        if !fm.fileExists(atPath: template.path), let source = SiteRenderer.builtInTemplate(SiteRenderer.searchTemplate) {
            try fm.createDirectory(at: template.deletingLastPathComponent(), withIntermediateDirectories: true)
            try source.write(to: template, atomically: true, encoding: .utf8)
            added = true
        }
        let page = root.appending(path: "pages/\(ContentItem.searchSlug).md")
        if !fm.fileExists(atPath: page.path),
           let starter = Bundle.main.url(forResource: "StarterSite", withExtension: nil)?
               .appending(path: "pages/\(ContentItem.searchSlug).md") {
            try fm.createDirectory(at: page.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: starter, to: page)
            added = true
        }
        return added
    }

    /// Creates pages/index.md for sites made before the Home page existed.
    /// Returns true if it was created.
    @discardableResult
    static func ensureHomePage(in root: URL, description: String) throws -> Bool {
        let url = root.appending(path: "pages/\(ContentItem.homeSlug).md")
        guard !FileManager.default.fileExists(atPath: url.path) else { return false }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var fm = FrontMatter()
        fm["title"] = .string("Home")
        try FrontMatter.serialize(fm, body: description).write(to: url, atomically: true, encoding: .utf8)
        return true
    }

    static let webFontsFile = "theme/fonts.json"

    private struct WebFontsFile: Codable {
        var fonts: [ThemeSettings.CustomFont]
    }

    static func loadWebFonts(from root: URL) -> [ThemeSettings.CustomFont] {
        guard let data = try? Data(contentsOf: root.appending(path: webFontsFile)),
              let file = try? JSONDecoder().decode(WebFontsFile.self, from: data)
        else { return [] }
        return file.fonts
    }

    func saveWebFonts() throws {
        let url = root.appending(path: Site.webFontsFile)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(WebFontsFile(fonts: webFonts)).write(to: url, options: .atomic)
    }

    func saveConfig() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(config).write(to: root.appending(path: Site.configFile), options: .atomic)
    }

    /// Turns a title into a URL-safe slug: "Hello, World!" → "hello-world".
    static func slugify(_ title: String) -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en"))
        var slug = ""
        var lastWasHyphen = true
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII {
                slug.unicodeScalars.append(scalar)
                lastWasHyphen = false
            } else if !lastWasHyphen {
                slug += "-"
                lastWasHyphen = true
            }
        }
        if slug.hasSuffix("-") { slug.removeLast() }
        return slug.isEmpty ? "untitled" : slug
    }
}

struct SiteError: LocalizedError {
    var message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
