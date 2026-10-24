import Foundation
import Testing
@testable import CardStock

struct SearchTests {
    let dir = FileManager.default.temporaryDirectory.appending(path: "cardstock-search-\(UUID().uuidString)")

    private func makeSite(_ pages: [String: String] = [:], _ change: (inout SiteConfig.Search) -> Void = { _ in }) throws -> Site {
        let root = dir.appending(path: "Site")
        try StarterSite.create(at: root, title: "Site")
        for (slug, text) in pages {
            try text.write(to: root.appending(path: "pages/\(slug).md"), atomically: true, encoding: .utf8)
        }
        var site = try Site.load(from: root)
        change(&site.config.search)
        return site
    }

    private func index(_ site: Site, drafts: Bool = false) throws -> [[String: Any]] {
        let json = try SiteRenderer(site: site, includeDrafts: drafts).render(path: SiteRenderer.searchIndexPath) ?? ""
        return try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
    }

    @Test func newSitesHaveASearchPage() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let site = try makeSite()
        let found = site.items.first(where: \.isSearchPage)
        let page = try #require(found)
        #expect(page.path == "/pages/search/" && page.isFixedPage && !page.canBeDeleted)
        let renderer = try SiteRenderer(site: site)
        #expect(renderer.paths.contains("/pages/search/") && renderer.paths.contains("/search.json"))
        let html = try #require(renderer.render(path: "/pages/search/"))
        #expect(html.contains(#"data-index="/search.json""#))
        #expect(html.contains(#"<input type="search" name="q" id="search-input" placeholder="Search""#))
        #expect(html.contains("Search every page and post on this site."))
    }

    @Test func indexHasPublishedPagesAsPlainText() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let site = try makeSite([
            "recipes": "---\ntitle: Recipes\nsummary: Things to cook\n---\n\nA **café** recipe with [a link](/x/) & <b>more</b>.\n\n<!-- newsletter -->\n",
            "secret": "---\ntitle: Secret\ndraft: true\n---\n\nHidden.\n",
            "news": "---\ntitle: News\ntype: blog-category\n---\n",
            "hello": "---\ntitle: Hello\ntype: post\ndate: 2026-10-20\ntags: [baking]\ncategories: [news]\n---\n\nHi.\n",
        ])
        let entries = try index(site)
        let titles = Set(entries.compactMap { $0["title"] as? String })
        #expect(titles.contains("Recipes") && titles.contains("Hello"))
        #expect(!titles.contains("Secret"), "drafts aren't published")
        #expect(!titles.contains("News"), "categories are off by default")
        #expect(!titles.contains("Search") && !titles.contains("Template") && !titles.contains("Home"))
        let recipes = try #require(entries.first { $0["title"] as? String == "Recipes" })
        #expect(recipes["url"] as? String == "/pages/recipes/" && recipes["type"] as? String == "Page")
        #expect(recipes["summary"] as? String == "Things to cook")
        #expect(recipes["text"] as? String == "A café recipe with a link & more.")
        let hello = try #require(entries.first { $0["title"] as? String == "Hello" })
        #expect(hello["date"] as? String == "October 20, 2026")
        #expect(hello["tags"] as? [String] == ["baking", "News"])
        #expect(try index(site, drafts: true).contains { $0["title"] as? String == "Secret" }, "the preview finds drafts")
    }

    @Test func pickedTypesOnly() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let site = try makeSite(["hello": "---\ntitle: Hello\ntype: post\n---\n", "about2": "---\ntitle: About Two\n---\n"]) {
            $0.kinds = ["post"]
        }
        let titles = try index(site).compactMap { $0["title"] as? String }
        #expect(titles.contains("Hello") && !titles.contains("About Two"))
    }

    @Test func searchBoxInPages() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let site = try makeSite(["find": "---\ntitle: Find\n---\n\n<!-- search -->\n\n```\n<!-- search -->\n```\n"]) {
            $0.placeholder = "Find a recipe"
            $0.buttonLabel = "Go"
        }
        let renderer = try SiteRenderer(site: site)
        let html = try #require(renderer.render(path: "/pages/find/"))
        #expect(html.components(separatedBy: #"<form class="search-box""#).count == 2, "one box; the line in code stays code")
        #expect(html.contains(#"<form class="search-box" action="/pages/search/" method="get" role="search"><input type="search" name="q" placeholder="Find a recipe" aria-label="Find a recipe"><button class="button" type="submit">Go</button></form>"#))
        #expect(html.components(separatedBy: ".search-box {").count == 2, "styles once")
        #expect(PageWidget.search.isUsed(in: site.items.first { $0.slug == "find" }!.body))
    }

    @Test func turnedOff() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let site = try makeSite(["find": "---\ntitle: Find\n---\n\n<!-- search -->\n"]) { $0.enabled = false }
        let renderer = try SiteRenderer(site: site)
        #expect(!renderer.paths.contains("/pages/search/") && !renderer.paths.contains("/search.json"))
        #expect(!(renderer.render(path: "/pages/find/") ?? "").contains("search-box"))
        #expect((try SiteRenderer(site: site, includeDrafts: true).render(path: "/pages/find/") ?? "").contains("Search is off"))
    }

    @Test func olderSitesGetTheSearchPage() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = dir.appending(path: "Site")
        try StarterSite.create(at: root, title: "Site")
        try FileManager.default.removeItem(at: root.appending(path: "pages/search.md"))
        try FileManager.default.removeItem(at: root.appending(path: "theme/search.html"))
        // Still rendered from the built-in template before the files come back.
        let before = try Site.load(from: root)
        #expect((try SiteRenderer(site: before).render(path: "/pages/search/") ?? "").contains("search-form"))
        #expect(try Site.ensureSearchPage(in: root))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "pages/search.md").path))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "theme/search.html").path))
        #expect(try !Site.ensureSearchPage(in: root))
    }

    @Test func savesAndLoads() throws {
        var config = SiteConfig()
        config.search.enabled = false
        config.search.kinds = ["post"]
        let decoded = try JSONDecoder().decode(SiteConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded == config)
        let old = try JSONDecoder().decode(SiteConfig.self, from: Data(#"{"title":"Old"}"#.utf8))
        #expect(old.search == SiteConfig.Search())
    }
}
