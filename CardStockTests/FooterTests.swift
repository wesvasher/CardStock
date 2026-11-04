import Foundation
import Testing
@testable import CardStock

struct FooterTests {
    let dir = FileManager.default.temporaryDirectory.appending(path: "cardstock-footer-\(UUID().uuidString)")

    private func render(_ change: (inout SiteConfig) -> Void) throws -> String {
        let root = dir.appending(path: "Site")
        if !FileManager.default.fileExists(atPath: root.path) { try StarterSite.create(at: root, title: "Site") }
        var site = try Site.load(from: root)
        change(&site.config)
        return try SiteRenderer(site: site).render(path: "/pages/about/") ?? ""
    }

    private func footer(_ html: String) -> String? {
        guard let start = html.range(of: "<footer"), let end = html.range(of: "</footer>") else { return nil }
        return String(html[start.lowerBound..<end.upperBound])
    }

    @Test func footerLine() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        // Defaults leave the theme's own line alone.
        #expect(!(try render { _ in }).contains(".site-footer { margin-top"))
        var html = try render { $0.footer.line.show = false }
        #expect(html.contains("<style>.site-footer { margin-top: 64px; padding-top: 24px; border-top: none; }</style>"))
        html = try render { $0.footer.line.spaceAbove = 32; $0.footer.line.padding = 8 }
        #expect(html.contains("<style>.site-footer { margin-top: 32px; padding-top: 8px; }</style>"))
        html = try render { $0.footer.line.show = false; $0.footer.enabled = false }
        #expect(!html.contains(".site-footer { margin-top"))
        let old = try JSONDecoder().decode(SiteConfig.self, from: Data(#"{"footer":{"enabled":true}}"#.utf8))
        #expect(old.footer.line.isDefault)
    }

    @Test func defaultsMatchTheOldFooter() throws {
        let old = #"{"title":"Old","author":"Ann Lee"}"#
        let config = try JSONDecoder().decode(SiteConfig.self, from: Data(old.utf8))
        #expect(config.footer.enabled && config.footer.showCopyright && config.footer.showFeed)
        #expect(config.copyrightText(year: 2026) == "© 2026 Ann Lee")
    }

    @Test func rendersSettings() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        var html = try render { config in
            config.author = "Ann"
            config.footer.copyrightName = "Ann Lee Studio"
            config.footer.links = [.init(title: "Privacy Policy", url: "/privacy-policy/")]
            config.footer.showFeed = false
        }
        let f = try #require(footer(html))
        #expect(f.contains("Ann Lee Studio"))
        #expect(f.contains(#"<a href="/privacy-policy/">Privacy Policy</a>"#))
        #expect(!f.contains("feed.xml"))

        html = try render { $0.footer.enabled = false }
        #expect(footer(html) == nil)

        html = try render { $0.footer.showCopyright = false }
        #expect(footer(html)?.contains("©") == false)
    }

    @Test func rendersLogo() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        var html = try render { config in
            config.footer.logo.image = "/media/files/logo.png"
            config.footer.logo.width = 120
            config.footer.logo.height = 40
            config.footer.logo.alt = "Ann Lee Studio"
        }
        var f = try #require(footer(html))
        let img = #"<img class="footer-logo" src="/media/files/logo.png" alt="Ann Lee Studio" style="width:120px;height:40px">"#
        #expect(f.contains(img))
        // Left: before the copyright, no row below.
        #expect(f.range(of: img)!.lowerBound < f.range(of: "©")!.lowerBound)
        #expect(!f.contains("footer-logo-row"))

        html = try render { config in
            config.footer.logo.image = "media/files/logo.png"
            config.footer.logo.placement = .below
            config.footer.logo.paddingTop = 24
            config.footer.logo.paddingBottom = 8
        }
        f = try #require(footer(html))
        #expect(f.contains(#"<div class="footer-logo-row" style="padding-top:24px;padding-bottom:8px"><img class="footer-logo" src="/media/files/logo.png" alt="Site" style="">"#))
        #expect(f.range(of: "footer-logo")!.lowerBound > f.range(of: "©")!.lowerBound)

        html = try render { _ in }
        #expect(footer(html)?.contains("footer-logo") == false)
    }

    @Test func phoneLayouts() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        // Stacked and centered by default, for every site.
        var html = try render { _ in }
        #expect(html.contains("@media (max-width: 600px)"))
        #expect(html.contains(".footer-row { flex-direction: column; flex-wrap: nowrap; align-items: center; text-align: center;"))
        #expect(html.contains(".footer-menu ul { position: static;"))

        html = try render { $0.footer.phoneLayout = .stackLeft }
        #expect(html.contains("align-items: flex-start; text-align: left;"))

        // One row: the theme's own wrapping, no extra CSS.
        html = try render { $0.footer.phoneLayout = .row }
        #expect(!html.contains(".footer-row { flex-direction: column"))
        #expect(SiteRenderer.footerPhoneStyle({ var f = SiteConfig.Footer(); f.phoneLayout = .row; return f }()) == nil)

        // The logo's size on phones.
        html = try render { config in
            config.footer.phoneLayout = .row
            config.footer.logo.image = "/media/files/logo.png"
            config.footer.logo.width = 120
            config.footer.logo.height = 40
            config.footer.logo.phoneSize = 50
        }
        #expect(html.contains(".footer-logo { width: 60px !important; height: 20px !important; }"))

        // Footer off: nothing.
        html = try render { $0.footer.enabled = false }
        #expect(!html.contains("@media (max-width: 600px) {\n  .site-footer"))

        let old = try JSONDecoder().decode(SiteConfig.self, from: Data(#"{"footer":{"logo":{"image":"/a.png"}}}"#.utf8))
        #expect(old.footer.phoneLayout == .stackCentered && old.footer.logo.phoneSize == 100)
        let saved = try JSONEncoder().encode({ var c = SiteConfig(); c.footer.phoneLayout = .stackLeft; return c }())
        #expect(String(decoding: saved, as: UTF8.self).contains(#""phoneLayout":"left""#))
    }

    /// The previews' page shows only the footer and is never published.
    @Test func footerPreviewPage() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = dir.appending(path: "Site")
        try StarterSite.create(at: root, title: "Site")
        let site = try Site.load(from: root)
        let renderer = try SiteRenderer(site: site, includeDrafts: true)
        let html = try #require(renderer.render(path: SiteRenderer.footerPreviewPath))
        #expect(html.contains(#"<footer class="site-footer">"#))
        #expect(html.contains("body > *:not(.site-footer):not(script)"))
        #expect(!renderer.paths.contains(SiteRenderer.footerPreviewPath))
    }

    @Test func darkFooterLogo() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = dir.appending(path: "Site")
        try StarterSite.create(at: root, title: "Site")
        var site = try Site.load(from: root)
        site.config.footer.logo.image = "/media/files/logo.png"
        site.config.footer.logo.darkImage = "media/files/logo-dark.png"
        site.theme = site.theme ?? ThemeSettings()

        // Auto: swapped in on devices set to dark, in both placements.
        site.theme?.appearance = .auto
        for placement in SiteConfig.Footer.Logo.Placement.allCases {
            site.config.footer.logo.placement = placement
            let html = try SiteRenderer(site: site).render(path: "/pages/about/") ?? ""
            #expect(html.contains(#"<picture class="logo-picture"><source media="(prefers-color-scheme: dark)" srcset="/media/files/logo-dark.png"><img class="footer-logo" src="/media/files/logo.png""#))
            #expect(html.components(separatedBy: ".logo-picture { display: contents; }").count == 2)
        }

        // Always dark: the dark logo outright. Always light: never.
        site.theme?.appearance = .dark
        var html = try SiteRenderer(site: site).render(path: "/pages/about/") ?? ""
        #expect(html.contains(#"<img class="footer-logo" src="/media/files/logo-dark.png""#))
        #expect(!html.contains("<picture"))
        site.theme?.appearance = .light
        html = try SiteRenderer(site: site).render(path: "/pages/about/") ?? ""
        #expect(!html.contains("logo-dark") && !html.contains("<picture"))

        let old = try JSONDecoder().decode(SiteConfig.self, from: Data(#"{"footer":{"logo":{"image":"/a.png"}}}"#.utf8))
        #expect(old.footer.logo.darkImage.isEmpty)
    }

    @Test func readsLinksFromALinkMenuPage() {
        let text = """
        [My Channel](https://www.youtube.com/@ann)
        https://www.linkedin.com/in/ann.
        - [Email me](mailto:ann@example.com "Say hi")
        Some words, then https://ann.substack.com and [About](/pages/about/)
        """
        let links = LinkMenu.links(in: text)
        #expect(links.map(\.title) == ["My Channel", "LinkedIn", "Email me", "Substack", "About"])
        #expect(links.map(\.url) == ["https://www.youtube.com/@ann", "https://www.linkedin.com/in/ann",
                                    "mailto:ann@example.com", "https://ann.substack.com", "/pages/about/"])
        #expect(links[0].isExternal && !links[4].isExternal)
        #expect(LinkMenu.name(for: "https://example.org/x") == "example.org")
    }

    @Test func rendersDropMenus() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = dir.appending(path: "Site")
        try StarterSite.create(at: root, title: "Site")
        try "---\ntitle: Social\ntype: links\n---\n[YouTube](https://youtube.com/@ann)\nhttps://github.com/ann\n"
            .write(to: root.appending(path: "pages/social.md"), atomically: true, encoding: .utf8)
        try "---\ntitle: Empty\ntype: links\n---\n"
            .write(to: root.appending(path: "pages/empty.md"), atomically: true, encoding: .utf8)
        var site = try Site.load(from: root)
        #expect(site.items(.links).first { $0.slug == "social" }?.isLinkMenu == true)
        site.config.footer.menus = [.init(title: "Follow", page: "social"),
                                    .init(title: "Nothing", page: "empty"),
                                    .init(title: "Gone", page: "missing")]
        let renderer = try SiteRenderer(site: site)
        // Link menus aren't pages of their own.
        #expect(!renderer.paths.contains("/social/"))
        let f = try #require(footer(renderer.render(path: "/pages/about/") ?? ""))
        #expect(f.contains(#"<details class="footer-menu"><summary>Follow</summary><ul><li><a href="https://youtube.com/@ann" target="_blank" rel="noopener">YouTube</a></li><li><a href="https://github.com/ann" target="_blank" rel="noopener">GitHub</a></li></ul></details>"#))
        // Menus with no links, or no page, are left out.
        #expect(!f.contains("Nothing") && !f.contains("Gone"))
        #expect(f.range(of: "footer-menu")!.lowerBound < f.range(of: #"class="rss""#)!.lowerBound)
    }

    @Test func rendersAttribution() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        var html = try render { _ in }
        #expect(footer(html)?.contains("attribution") == false)

        html = try render { $0.footer.attribution.enabled = true }
        #expect(footer(html)?.contains(#"<a class="attribution" href="https://github.com/wesvasher/CardStock" target="_blank" rel="noopener">Designed with CardStock</a>"#) == true)

        html = try render { config in
            config.footer.attribution.enabled = true
            config.footer.attribution.text = "Made with CardStock"
        }
        #expect(footer(html)?.contains(">Made with CardStock</a>") == true)
    }

    @Test func savesAndLoads() throws {
        var config = SiteConfig()
        config.footer.links = [.init(title: "Terms", url: "/terms/")]
        config.footer.enabled = false
        config.footer.logo.image = "/media/files/logo.svg"
        config.footer.logo.placement = .below
        config.footer.logo.paddingTop = 30
        config.footer.menus = [.init(title: "Follow", page: "social")]
        config.footer.attribution.enabled = true
        config.footer.attribution.text = "Built with CardStock"
        let decoded = try JSONDecoder().decode(SiteConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded == config)
    }
}
