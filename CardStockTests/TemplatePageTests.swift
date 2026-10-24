import Foundation
import Testing
@testable import CardStock

struct TemplatePageTests {
    let dir = FileManager.default.temporaryDirectory.appending(path: "cardstock-templatepage-\(UUID().uuidString)")

    private func starter() throws -> URL {
        let root = dir.appending(path: "Site")
        try StarterSite.create(at: root, title: "Site")
        return root
    }

    @Test func isAFixedPageInPagesButNeverPublished() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let site = try Site.load(from: try starter())
        let found = site.items.first { $0.isTemplatePage }
        let page = try #require(found)
        #expect(page.title == "Template")
        #expect(page.kind == .page && !page.canBeDeleted)
        #expect(page.path == SiteRenderer.templatePagePath)

        let renderer = try SiteRenderer(site: site)
        let html = try #require(renderer.render(path: SiteRenderer.templatePagePath))
        #expect(html.contains("<h1>Template</h1>"))
        #expect(html.contains("Change fonts, colors and layout in Configuration"))
        #expect(html.contains(#"class="button buy""#) && html.contains(#"class="post-list""#))
        #expect(html.contains(#"class="site-bar "#) && html.contains("site-footer"))
        #expect(!renderer.paths.contains(SiteRenderer.templatePagePath))
    }

    @Test func olderSitesGetTheTemplatePage() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = try starter()
        let template = root.appending(path: "theme/template.html")
        let page = root.appending(path: "pages/template.md")
        try FileManager.default.removeItem(at: template)
        try FileManager.default.removeItem(at: page)
        // Missing: the built-in template still shows in the preview.
        #expect(try SiteRenderer(site: try Site.load(from: root)).render(path: SiteRenderer.templatePagePath) != nil)
        #expect(try Site.ensureTemplatePage(in: root))
        #expect(FileManager.default.fileExists(atPath: template.path))
        #expect(FileManager.default.fileExists(atPath: page.path))
        #expect(try !Site.ensureTemplatePage(in: root))
    }
}
