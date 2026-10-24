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
