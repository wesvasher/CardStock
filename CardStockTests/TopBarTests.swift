import Foundation
import Testing
@testable import CardStock

struct TopBarTests {
    let dir = FileManager.default.temporaryDirectory.appending(path: "cardstock-topbar-\(UUID().uuidString)")

    private func render(_ change: (inout SiteConfig.Header) -> Void) throws -> String {
        let root = dir.appending(path: "Site")
        if !FileManager.default.fileExists(atPath: root.path) { try StarterSite.create(at: root, title: "Site") }
        var site = try Site.load(from: root)
        change(&site.config.header)
        return try SiteRenderer(site: site).render(path: "/pages/about/") ?? ""
    }

    @Test func scrollsAwayByDefault() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let html = try render { _ in }
        #expect(html.contains(#"<div class="site-bar has-mobile-menu" style="--bar-h:88px;--bar-h-compact:88px;--logo-h:40px;--logo-h-compact:40px">"#))
        #expect(html.contains(#"<a class="site-title" href="/"><span class="title-text">Site</span></a>"#))
        #expect(!html.contains("site-bar-spacer") && !html.contains("<script>\n    // Shrinks"))
    }

    @Test func fixedBarWithLogo() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let html = try render { header in
            header.mode = .fixed
            header.logo = "media/files/logo.svg"
            header.showTitle = false
            header.height = 72
        }
        #expect(html.contains(#"<div class="site-bar is-fixed has-mobile-menu" style="--bar-h:72px;--bar-h-compact:72px;"#))
        // Without the title, the logo carries the site's name.
        #expect(html.contains(#"<img class="logo logo-large" src="/media/files/logo.svg" alt="Site">"#))
        #expect(!html.contains("title-text"))
        #expect(html.contains("site-bar-spacer") && !html.contains("Shrinks the top bar"))
    }

    @Test func shrinkingBarSwapsLogos() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let html = try render { header in
            header.mode = .shrinking
            header.logo = "/media/files/logo.png"
            header.compactLogo = "/media/files/icon.png"
            header.height = 100
            header.compactHeight = 60
            header.logoHeight = 64
            header.compactLogoHeight = 32
        }
        #expect(html.contains(#"<div class="site-bar is-fixed shrinks has-compact-logo has-mobile-menu" style="--bar-h:100px;--bar-h-compact:60px;--logo-h:64px;--logo-h-compact:32px;--logo-k:0.5">"#))
        #expect(html.contains(#"<img class="logo logo-compact" src="/media/files/icon.png" alt="" aria-hidden="true">"#))
        #expect(html.contains("<span class=\"title-text\">Site</span>"))
        #expect(html.contains("Shrinks the top bar"))
    }

    @Test func savesAndLoads() throws {
        var config = SiteConfig()
        config.header.mode = .shrinking
        config.header.compactLogo = "/media/files/icon.svg"
        config.header.compactHeight = 50
        let decoded = try JSONDecoder().decode(SiteConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded == config)
        let old = try JSONDecoder().decode(SiteConfig.self, from: Data(#"{"title":"Old"}"#.utf8))
        #expect(old.header == SiteConfig.Header())
    }

    @Test func linkGroups() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = dir.appending(path: "Site")
        try StarterSite.create(at: root, title: "Site")
        var site = try Site.load(from: root)
        site.config.nav = [.init(title: "About", url: "/pages/about/")]
        site.config.header.showLeftLinks = true
        site.config.header.leftLinks = [.init(title: "Shop", url: "/shop/")]
        site.config.header.centerLinks = [.init(title: "Hidden", url: "/hidden/")]
        var html = try SiteRenderer(site: site).render(path: "/pages/about/") ?? ""
        #expect(html.contains(#"<div class="bar-slot bar-left has-brand"><a class="site-title" href="/"><span class="title-text">Site</span></a><nav><a href="/shop/"><span>Shop</span></a></nav></div>"#))
        // Off groups keep their links but don't show them.
        #expect(html.contains(#"<div class="bar-slot bar-center"></div>"#))
        #expect(html.contains(#"<div class="bar-slot bar-right"><nav><a href="/pages/about/" aria-current="page"><span>About</span></a></nav></div>"#))
        #expect(site.config.menuLinks.map(\.title) == ["Shop", "About"])

        site.config.header.showRightLinks = false
        html = try SiteRenderer(site: site).render(path: "/pages/about/") ?? ""
        #expect(html.contains(#"<div class="bar-slot bar-right"></div>"#))
        #expect(site.config.menuLinks.map(\.title) == ["Shop"])
    }

    @Test func logoPositionPaddingAndSize() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let html = try render { header in
            header.logo = "/media/files/logo.png"
            header.logoWidth = 120
            header.logoHeight = 40
            header.logoAlt = "Acme"
            header.showTitle = false
            header.logoPosition = .right
            header.logoPadding = .init(top: 4, right: 0, bottom: 6, left: 12)
        }
        #expect(html.contains(#"has-logo-width has-mobile-menu" style="--bar-h:88px;--bar-h-compact:88px;--logo-h:40px;--logo-h-compact:40px;--logo-w:120px">"#))
        #expect(html.contains(#"<div class="bar-slot bar-left"></div>"#))
        #expect(html.contains(#"<a class="site-title" href="/" style="padding:4px 0px 6px 12px"><span class="logo-box"><img class="logo logo-large" src="/media/files/logo.png" alt="Acme">"#))
        #expect(html.contains(#"</nav><a class="site-title""#), "the logo comes after the right-hand links")
    }

    @Test func hiddenLogoKeepsSettings() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let html = try render { header in
            header.logo = "/media/files/logo.png"
            header.logoWidth = 120
            header.compactLogo = "/media/files/icon.png"
            header.mode = .shrinking
            header.showTitle = false
            header.showLogo = false
        }
        #expect(!html.contains("logo-large") && !html.contains("logo-compact") && !html.contains("--logo-w"))
        // The title stays off too, so the bar shows just its links.
        #expect(!html.contains("site-title"))
        let old = try JSONDecoder().decode(SiteConfig.self, from: Data(#"{"header":{"logo":"/a.png"}}"#.utf8))
        #expect(old.header.showLogo && old.header.isLogoShown)
    }

    @Test func titleWithoutLogo() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let html = try render { header in
            header.logo = "/media/files/logo.png"
            header.showLogo = false
        }
        #expect(html.contains(#"<a class="site-title" href="/"><span class="title-text">Site</span></a>"#))
    }

    @Test func svgLogoHasNoWidth() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let html = try render { header in
            header.logo = "/media/files/logo.svg"
            header.logoWidth = 300
        }
        #expect(!html.contains("--logo-w") && !html.contains("has-logo-width"))
    }

    @Test func buttonsAndIcons() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = dir.appending(path: "Site")
        try StarterSite.create(at: root, title: "Site")
        var site = try Site.load(from: root)
        site.config.nav = [
            .init(title: "Shop", url: "/shop/", button: true, icon: "shopping-bag"),
            .init(title: "", url: "/pages/search/", icon: "search"),
            .init(title: "About", url: "/pages/about/"),
        ]
        let html = try SiteRenderer(site: site).render(path: "/pages/about/") ?? ""
        let bag = try #require(NavIcon.named("shopping-bag")).svg
        #expect(html.contains(#"<a href="/shop/" class="nav-button">"# + bag + "<span>Shop</span></a>"))
        // No text: just the icon, named for screen readers.
        #expect(html.contains(#"<a href="/pages/search/" aria-label="Search"><svg class="nav-icon""#))
        #expect(html.contains(#"<a href="/pages/about/" aria-current="page"><span>About</span></a>"#))
    }

    @Test func phoneMenuHasEveryLink() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = dir.appending(path: "Site")
        try StarterSite.create(at: root, title: "Site")
        var site = try Site.load(from: root)
        site.config.header.showLeftLinks = true
        site.config.header.leftLinks = [.init(title: "Work", url: "/work/")]
        site.config.nav = [.init(title: "Shop", url: "/shop/", button: true)]
        var html = try SiteRenderer(site: site).render(path: "/pages/about/") ?? ""
        #expect(html.contains("has-mobile-menu") && html.contains(#"<button class="nav-toggle""#))
        let overlay = try #require(html.components(separatedBy: #"<nav class="nav-overlay-links">"#).last?.components(separatedBy: "</nav>").first)
        #expect(overlay == #"<a href="/work/"><span>Work</span></a><a href="/shop/" class="nav-button"><span>Shop</span></a>"#)
        #expect(html.contains(#"<div class="bar-slot bar-left has-brand">"#))

        site.config.header.mobileMenu = false
        html = try SiteRenderer(site: site).render(path: "/pages/about/") ?? ""
        #expect(!html.contains("nav-overlay") && !html.contains("has-mobile-menu"))

        // No links, no menu button.
        site.config.header.mobileMenu = true
        site.config.header.showLeftLinks = false
        site.config.header.showRightLinks = false
        html = try SiteRenderer(site: site).render(path: "/pages/about/") ?? ""
        #expect(!html.contains("nav-toggle"))
    }

    @Test func plainLinksStaySmallInSiteJSON() throws {
        let json = String(decoding: try JSONEncoder().encode(SiteConfig.NavLink(title: "About", url: "/pages/about/")), as: UTF8.self)
        #expect(!json.contains("button") && !json.contains("icon"))
        let fancy = SiteConfig.NavLink(title: "Shop", url: "/shop/", button: true, icon: "store")
        #expect(try JSONDecoder().decode(SiteConfig.NavLink.self, from: JSONEncoder().encode(fancy)) == fancy)
    }

    @Test func iconsAreComplete() {
        #expect(Set(NavIcon.all.map(\.id)).count == NavIcon.all.count)
        for icon in NavIcon.all {
            #expect(!icon.inner.isEmpty && !icon.inner.contains("<svg") && NavIcon.groups.contains(icon.group), "\(icon.id)")
        }
    }

    @Test func oldHeadersKeepTheirMenu() throws {
        let old = try JSONDecoder().decode(SiteConfig.self, from: Data(#"{"nav":[{"title":"About","url":"/pages/about/"}],"header":{"logo":"/a.png","logoHeight":50}}"#.utf8))
        #expect(old.header.showRightLinks && !old.header.showLeftLinks && !old.header.showCenterLinks)
        #expect(old.header.logoPosition == .left && old.header.logoWidth == 0 && old.header.logoPadding.isZero)
        #expect(old.menuLinks.map(\.title) == ["About"])
    }
}

struct ComponentsTests {
    @Test func defaultsMatchTheOldLook() {
        let css = ThemeSettings().css
        #expect(css.contains("--button-radius: 6px;") && css.contains("--card-radius: 10px;"))
        #expect(css.contains("--card-border: 1px solid var(--line);") && css.contains("--card-shadow: none;"))
        #expect(css.contains("--image-radius: 0px;") && css.contains("--table-stripe: transparent;"))
        #expect(!css.contains("--button-bg"))
    }

    @Test func oldSettingsFollowTheirRadius() throws {
        let old = try JSONDecoder().decode(ThemeSettings.self, from: Data(#"{"radius":16}"#.utf8))
        #expect(old.buttonRadius == 12 && old.cardRadius == 20 && old.coverRadius == 16
                && old.codeRadius == 16 && old.menuRadius == 16 && old.imageRadius == 0)
    }

    @Test func choicesBecomeCSS() throws {
        var theme = ThemeSettings()
        theme.buttonStyle = .filled
        theme.cardBorder = false
        theme.cardShadow = .soft
        theme.quoteColor = .accent
        theme.tableStripes = true
        let css = theme.css
        #expect(css.contains("--button-bg: var(--accent);") && css.contains("--button-text: var(--bg);"))
        #expect(css.contains("--card-border: 1px solid transparent;"))
        #expect(css.contains("--card-shadow: 0 2px 10px"))
        #expect(css.contains("--quote-bar: var(--accent);"))
        #expect(!css.contains("--table-stripe: transparent;"))
        let decoded = try JSONDecoder().decode(ThemeSettings.self, from: JSONEncoder().encode(theme))
        #expect(decoded == theme)
    }

    @Test func topBarLinkStyle() throws {
        var theme = ThemeSettings()
        #expect(theme.css.contains("--nav-font: var(--font-heading);") && theme.css.contains("--nav-size: 15px;")
                && theme.css.contains("--nav-weight: 400;"))
        theme.navFont = "lora"
        theme.navSize = 18
        theme.navWeight = 600
        #expect(theme.css.contains(#"--nav-font: "Lora""#) && theme.css.contains("--nav-size: 18px;")
                && theme.css.contains("--nav-weight: 600;"))
        // A Google font used only for the links still gets loaded.
        #expect(theme.headHTML.contains("family=Lora"))
        let old = try JSONDecoder().decode(ThemeSettings.self, from: Data("{}".utf8))
        #expect(old.navFont.isEmpty && old.navSize == 15 && old.navWeight == 400)
    }

    @Test func linkColors() throws {
        var theme = ThemeSettings()
        // Unpicked colors follow the palette in each appearance.
        #expect(theme.css.contains("--nav-link: var(--muted);") && theme.css.contains("--nav-pressed: var(--nav-hover);"))
        theme.navLight.hover = "#ff0000"
        theme.navDark.link = "#00ff00"
        theme.navDark.pressed = "bad;color"
        let css = theme.css
        let dark = try #require(css.range(of: "@media (prefers-color-scheme: dark)"))
        #expect(css[..<dark.lowerBound].contains("--nav-hover: #ff0000;"))
        #expect(css[dark.lowerBound...].contains("--nav-link: #00ff00;"))
        #expect(css[dark.lowerBound...].contains("--nav-hover: var(--text);"))
        #expect(css.contains("--nav-pressed: inherit;"), "bad values are dropped")
        #expect(theme.navLight.resolved(.light).pressed == "#ff0000", "click follows hover")
        #expect(css.contains("--nav-icon: currentColor;"), "icons follow their link until picked")
        theme.navDark.icon = "#abcdef"
        theme.navButton.light.icon = "#123456"
        let iconCSS = theme.css
        let darkPart = try #require(iconCSS.range(of: "@media (prefers-color-scheme: dark)"))
        #expect(iconCSS[darkPart.lowerBound...].contains("--nav-icon: #abcdef;"))
        #expect(iconCSS[..<darkPart.lowerBound].contains("--navbtn-icon: #123456;"))
        #expect(theme.navLight.resolved(.light).icon == ThemeSettings.Palette.light.muted)
        let decoded = try JSONDecoder().decode(ThemeSettings.self, from: JSONEncoder().encode(theme))
        #expect(decoded == theme)
    }

    @Test func buttonStyle() throws {
        var theme = ThemeSettings()
        var css = theme.css
        #expect(css.contains("--navbtn-bg: var(--accent);") && css.contains("--navbtn-radius: 8px;")
                && css.contains("--navbtn-alpha: 100%;") && css.contains("--nav-icon-dir: row;"))
        theme.navButton.pill = true
        theme.navButton.opacity = 40
        theme.navButton.blur = 12
        theme.navButton.shadow = .soft
        theme.navButton.iconPosition = .right
        theme.navButton.dark.background = "#112233"
        css = theme.css
        #expect(css.contains("--navbtn-radius: 999px;") && css.contains("--navbtn-alpha: 40%;")
                && css.contains("--navbtn-blur: 12px;") && css.contains("--navbtn-shadow: 0 2px 10px")
                && css.contains("--nav-icon-dir: row-reverse;"))
        let dark = try #require(css.range(of: "@media (prefers-color-scheme: dark)"))
        #expect(css[dark.lowerBound...].contains("--navbtn-bg: #112233;"))
        #expect(theme.navButton.light.resolved(.light).background == ThemeSettings.Palette.light.accent)
        let decoded = try JSONDecoder().decode(ThemeSettings.self, from: JSONEncoder().encode(theme))
        #expect(decoded == theme)
    }

    @Test func pageLayoutSettings() throws {
        var theme = ThemeSettings()
        #expect(theme.css.contains("--measure: 60rem;") && theme.css.contains("--gutter: 20px;")
                && theme.css.contains("--bar-width: var(--measure);"), "960 px by default")
        theme.contentWidth = 1140.0 / 16
        theme.gutter = 32
        theme.fullWidthBars = true
        #expect(theme.css.contains("--measure: 71.25rem;") && theme.css.contains("--gutter: 32px;")
                && theme.css.contains("--bar-width: none;"))
        // Sites that saved a width keep it.
        let old = try JSONDecoder().decode(ThemeSettings.self, from: Data(#"{"contentWidth":40}"#.utf8))
        #expect(old.contentWidth == 40 && old.gutter == 20 && !old.fullWidthBars)
        #expect(ThemeSettings.popularContentWidths.contains { $0.px == 960 })
    }

    @Test func applyCornersToAll() {
        var theme = ThemeSettings()
        theme.radius = 4
        theme.applyRadiusToAll()
        #expect(theme.buttonRadius == 3 && theme.cardRadius == 5 && theme.coverRadius == 4
                && theme.codeRadius == 4 && theme.menuRadius == 4)
    }

    @Test func starterStylesheetUsesEveryVariable() throws {
        let url = try #require(Bundle.main.url(forResource: "StarterSite", withExtension: nil))
        let css = try String(contentsOf: url.appending(path: "theme/assets/style.css"), encoding: .utf8)
        for name in ["gutter", "bar-width", "nav-font", "nav-size", "nav-weight", "nav-link", "nav-hover", "nav-current", "nav-pressed",
                     "nav-icon-dir", "nav-icon", "navbtn-icon", "navbtn-bg", "navbtn-text", "navbtn-border", "navbtn-border-width", "navbtn-radius",
                     "navbtn-alpha", "navbtn-blur", "navbtn-shadow", "navbtn-pad-x", "navbtn-pad-y", "button-radius", "button-pad-x", "button-pad-y", "button-bg", "button-text", "card-radius",
                     "card-padding", "card-border", "card-shadow", "cover-radius", "image-radius", "code-radius",
                     "quote-bar", "quote-bar-width", "table-stripe", "menu-radius"] {
            #expect(css.contains("var(--\(name))"), "style.css doesn't use --\(name)")
        }
    }
}
