import Foundation
import Testing
@testable import CardStock

struct LayoutTests {
    let dir = FileManager.default.temporaryDirectory.appending(path: "cardstock-layouts-\(UUID().uuidString)")

    private func starter() throws -> URL {
        let root = dir.appending(path: "Site")
        try StarterSite.create(at: root, title: "Site")
        return root
    }

    /// Loads the starter site with one page changed.
    private func site(_ slug: String, layout: String, body: String? = nil) throws -> (Site, ContentItem) {
        var site = try Site.load(from: try starter())
        let i = try #require(site.items.firstIndex { $0.slug == slug })
        site.items[i].layout = layout
        if let body { site.items[i].body = body }
        return (site, site.items[i])
    }

    @Test func readsTheDescriptionComment() {
        let layout = PageLayout(id: "hero", source: """
        <!--
        name: Big Hero
        description: A hero.
        areas: Intro, Text
        main: Text
        types: page, post
        -->
        <h1>{{ page.title }}</h1>
        """)
        #expect(layout.name == "Big Hero" && layout.description == "A hero.")
        #expect(layout.areas == ["Intro", "Text"] && layout.mainArea == "Text")
        #expect(layout.types == ["page", "post"] && layout.suits(.post) && !layout.suits(.product))
        #expect(layout.source == "<h1>{{ page.title }}</h1>")

        let plain = PageLayout(id: "two-columns", source: "<div></div>")
        #expect(plain.name == "Two Columns" && plain.areas.isEmpty && plain.suits(.product))
    }

    @Test func splitsSectionsButNotInsideCode() {
        let text = "One\n\n<!-- section -->\n\nTwo\n```\n<!-- section -->\n```\n<!--SECTION-->\nThree"
        let sections = PageLayout.sections(of: text)
        #expect(sections == ["One", "Two\n```\n<!-- section -->\n```", "Three"])
        #expect(PageLayout.sections(of: "Just text") == ["Just text"])
    }

    @Test func fillsAreasInOrder() {
        let layout = PageLayout(id: "x", source: "<!--\nareas: Intro, Left, Right\nmain: Left\n-->")
        #expect(layout.areaText(["All"]) == [2: "All"])
        #expect(layout.areaText(["A", "B"]) == [1: "A", 2: "B"])
        #expect(layout.areaText(["A", "B", "C", "D"]) == [1: "A", 2: "B", 3: "C\n\nD"])
    }

    @Test func rendersAPageInALayout() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let (site, about) = try site("about", layout: "hero", body: "The intro.\n\n<!-- section -->\n\nThe rest.")
        let html = try SiteRenderer(site: site).render(about)
        let hero = try #require(html.range(of: #"class="layout-hero""#))
        let intro = try #require(html.range(of: "<p>The intro.</p>"))
        let rest = try #require(html.range(of: "<p>The rest.</p>"))
        #expect(hero.lowerBound < intro.lowerBound && intro.lowerBound < rest.lowerBound)
        #expect(!html.contains("areas: Intro"))  // the description comment isn't published
        #expect(html.contains("site-footer"))
    }

    @Test func postsKeepTheirDetailsInAnyLayout() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let (site, post) = try site("hello-world", layout: "sidebar")
        let html = try SiteRenderer(site: site).render(post)
        #expect(html.contains(#"<p class="meta"><time datetime=""#))
        #expect(html.contains(#"<a class="category" href="/blog/notes/">"#))
        #expect(html.contains("Recent posts") && html.contains("Categories"))
    }

    @Test func missingLayoutsUseStandard() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let (site, about) = try site("about", layout: "nope")
        let html = try SiteRenderer(site: site).render(about)
        #expect(!html.contains("layout-") && html.contains("<article>"))
        let check = SiteInsights.healthChecks(site, files: [], outdatedThemeFiles: []).first { $0.id == "layouts" }
        #expect(check?.passed == false)
    }

    @Test func previewSamplesAreNeverPublished() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let renderer = try SiteRenderer(site: try Site.load(from: try starter()))
        let html = try #require(renderer.render(path: SiteRenderer.layoutPreviewPath("two-columns")))
        #expect(html.contains("layout-columns-grid") && html.contains("The third section"))
        #expect(renderer.render(path: SiteRenderer.layoutPreviewPath("")) != nil)
        #expect(!renderer.paths.contains { $0.hasPrefix(SiteRenderer.layoutPreviewPrefix) })
    }

    @Test func olderSitesGetTheLayouts() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = try starter()
        let folder = root.appending(path: PageLayout.folder)
        try FileManager.default.removeItem(at: folder)
        // Without the folder, the built-in layouts are used.
        #expect(PageLayout.load(root: root).map(\.id).contains("hero"))
        #expect(try PageLayout.ensureLayouts(in: root))
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "hero.html").path))
        #expect(try !PageLayout.ensureLayouts(in: root))
    }
}
