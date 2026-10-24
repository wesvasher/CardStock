import Foundation
import Testing
@testable import CardStock

struct NewsletterTests {
    let dir = FileManager.default.temporaryDirectory.appending(path: "cardstock-newsletter-\(UUID().uuidString)")

    private func site(page body: String, _ change: (inout SiteConfig.Newsletter) -> Void = { _ in }) throws -> Site {
        let root = dir.appending(path: "Site")
        try StarterSite.create(at: root, title: "Site")
        try "---\ntitle: Join\n---\n\n\(body)\n".write(to: root.appending(path: "pages/join.md"), atomically: true, encoding: .utf8)
        var site = try Site.load(from: root)
        change(&site.config.newsletter)
        return site
    }

    @Test func boxReplacesTheLine() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let site = try site(page: "Before.\n\n<!-- newsletter -->\n\nAfter.") {
            $0.embed = #"<iframe src="https://example.com/embed"></iframe>"#
            $0.alignment = .center
        }
        let html = try SiteRenderer(site: site).render(path: "/join/") ?? ""
        #expect(html.contains(#"<section class="newsletter newsletter-card newsletter-center"><h2>Subscribe to the newsletter</h2><p>Get new posts by email. Unsubscribe any time.</p><div class="newsletter-embed"><iframe src="https://example.com/embed"></iframe></div></section>"#))
        #expect(html.contains(".newsletter-card {"))
        #expect(!html.contains("<!-- newsletter -->"))
    }

    @Test func linesInCodeStayText() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let site = try site(page: "```\n<!-- newsletter -->\n```") { $0.embed = "<form></form>" }
        let html = try SiteRenderer(site: site).render(path: "/join/") ?? ""
        #expect(!html.contains("newsletter-embed"))
        #expect(!SiteConfig.Newsletter.isUsed(in: site.items.first { $0.slug == "join" }!.body))
    }

    @Test func withoutEmbedCodeOnlyThePreviewShowsANote() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let site = try site(page: "<!-- Newsletter -->")
        let published = try SiteRenderer(site: site).render(path: "/join/") ?? ""
        #expect(!published.contains("class=\"newsletter") && !published.contains("<!-- Newsletter -->"))
        let preview = try SiteRenderer(site: site, includeDrafts: true).render(path: "/join/") ?? ""
        #expect(preview.contains("newsletter-missing"))
        let check = SiteInsights.healthChecks(site, files: [], outdatedThemeFiles: []).first { $0.id == "newsletter" }
        #expect(check?.problems.first?.action == .newsletter)
    }

    @Test func headingIsEscapedAndPreviewPageExists() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let site = try site(page: "Hi") {
            $0.embed = "<form></form>"
            $0.heading = "News & <notes>"
            $0.text = ""
            $0.style = .plain
        }
        let html = try SiteRenderer(site: site, includeDrafts: true).render(path: SiteRenderer.newsletterPreviewPath) ?? ""
        #expect(html.contains(#"<section class="newsletter newsletter-plain newsletter-left"><h2>News &amp; &lt;notes&gt;</h2><div class="newsletter-embed"><form></form></div>"#))
        #expect(!(try SiteRenderer(site: site).paths).contains(SiteRenderer.newsletterPreviewPath))
    }

    @Test func savesAndLoads() throws {
        var config = SiteConfig()
        config.newsletter.embed = "<script src=\"x.js\"></script>"
        config.newsletter.style = .plain
        let decoded = try JSONDecoder().decode(SiteConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded == config)
        let old = try JSONDecoder().decode(SiteConfig.self, from: Data(#"{"title":"Old"}"#.utf8))
        #expect(old.newsletter == SiteConfig.Newsletter())
    }
}
