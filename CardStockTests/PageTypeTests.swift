import Foundation
import Testing
@testable import CardStock

struct PageTypeTests {
    let dir = FileManager.default.temporaryDirectory.appending(path: "cardstock-types-\(UUID().uuidString)")

    private func starter() throws -> URL {
        let root = dir.appending(path: "Site")
        try StarterSite.create(at: root, title: "Site")
        return root
    }

    private func write(_ text: String, _ path: String, in root: URL) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func typeComesFromFrontMatter() {
        var item = ContentItem(fileURL: URL(filePath: "/s/pages/mug.md"), text: "---\ntitle: Mug\ntype: product\n---\n")
        #expect(item.kind == .product && item.path == "/shop/mug/")
        item.kind = .page
        #expect(item.frontMatter["type"] == nil && item.path == "/mug/")
        item.kind = .post
        #expect(item.frontMatter.string("type") == "post" && !item.date.isEmpty && item.path == "/posts/mug/")
        // Home is always a static page.
        let home = ContentItem(fileURL: URL(filePath: "/s/pages/index.md"), text: "---\ntitle: Home\ntype: post\n---\n")
        #expect(home.kind == .page && home.path == "/")
    }

    @Test func movesOldFoldersIntoPages() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = try starter()
        try write("---\ntitle: Old Post\ndate: 2025-05-01\n---\nHi", "posts/old-post.md", in: root)
        try write("---\ntitle: About Clash\ndate: 2025-05-01\n---\nPost named like a page", "posts/about.md", in: root)
        try write("---\ntitle: Bridge\nlink: https://example.com\n---\nBuilt it", "projects/bridge.md", in: root)
        var site = try Site.load(from: root)
        site.config.nav.append(.init(title: "Portfolio", url: "/portfolio/"))
        site.config.nav.append(.init(title: "Contact", url: "/portfolio/"))
        try site.saveConfig()

        let result = try SiteMigration.run(in: root)
        #expect(result == .init(posts: 2, projects: 1))
        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: root.appending(path: "posts").path))
        #expect(!fm.fileExists(atPath: root.appending(path: "projects").path))

        site = try Site.load(from: root)
        let old = try #require(site.items.first { $0.slug == "old-post" })
        #expect(old.kind == .post && old.path == "/posts/old-post/" && old.body == "Hi")
        // A post whose name a page already had gets a new name, and a redirect.
        #expect(site.items.first { $0.slug == "about-2" }?.kind == .post)
        let bridge = try #require(site.items.first { $0.slug == "bridge" })
        #expect(bridge.kind == .page && bridge.path == "/bridge/")
        #expect(!site.config.nav.contains { $0.title == "Portfolio" })
        #expect(site.config.nav.contains { $0.title == "Contact" })

        let redirects = try String(contentsOf: root.appending(path: "static/_redirects"), encoding: .utf8)
        #expect(redirects.contains("/portfolio/bridge/ /bridge/ 301"))
        #expect(redirects.contains("/posts/about/ /posts/about-2/ 301"))
        #expect(redirects.contains("/portfolio/ / 301"))

        // Nothing to do the second time.
        #expect(try SiteMigration.run(in: root).isEmpty)
    }

    @Test func categoriesListTheirPostsAndProducts() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = try starter()
        try write("---\ntype: blog-category\ntitle: Travel\n---\nTrips I took.", "pages/travel.md", in: root)
        try write("---\ntype: post\ntitle: Kyoto\ndate: 2026-03-01\ncategories: [travel, notes]\n---\nTemples", "pages/kyoto.md", in: root)
        try write("---\ntype: post\ntitle: Secret Trip\ndate: 2026-04-01\ndraft: true\ncategories: [travel]\n---\n", "pages/secret-trip.md", in: root)
        try write("---\ntype: shop-category\ntitle: Cups\n---\nThings to drink from.", "pages/cups.md", in: root)
        try write("---\ntype: product\ntitle: Blue Mug\nprice: $24\nbuy: https://buy.stripe.com/abc\ncategories: [cups]\n---\nA mug.", "pages/blue-mug.md", in: root)
        try write("---\ntype: product\ntitle: Plate\nprice: $30\n---\n", "pages/plate.md", in: root)

        let renderer = try SiteRenderer(site: Site.load(from: root))
        let paths = renderer.paths
        #expect(paths.contains("/blog/travel/") && paths.contains("/shop/cups/") && paths.contains("/shop/blue-mug/") && paths.contains("/shop/"))

        let travel = try #require(renderer.render(path: "/blog/travel/"))
        #expect(travel.contains("Trips I took.") && travel.contains(#"href="/posts/kyoto/""#))
        #expect(!travel.contains("Secret Trip"))

        let kyoto = try #require(renderer.render(path: "/posts/kyoto/"))
        #expect(kyoto.contains(#"<a class="category" href="/blog/travel/">Travel</a>"#))
        #expect(kyoto.contains(#"<a class="category" href="/blog/notes/">Notes</a>"#))

        let cups = try #require(renderer.render(path: "/shop/cups/"))
        #expect(cups.contains(#"href="/shop/blue-mug/""#) && cups.contains("$24") && !cups.contains("Plate"))

        let mug = try #require(renderer.render(path: "/shop/blue-mug/"))
        #expect(mug.contains(#"<p class="price">$24</p>"#))
        #expect(mug.contains(#"<a class="button buy" href="https://buy.stripe.com/abc" target="_blank" rel="noopener">Buy Now</a>"#))

        let shop = try #require(renderer.render(path: "/shop/"))
        #expect(shop.contains("Blue Mug") && shop.contains("Plate"))
    }

    @Test func olderThemesUseBuiltInTemplates() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = try starter()
        for name in SiteRenderer.newerTemplateNames {
            try FileManager.default.removeItem(at: root.appending(path: "theme/\(name).html"))
        }
        try write("---\ntype: product\ntitle: Mug\nprice: $5\n---\n", "pages/mug.md", in: root)
        let html = try SiteRenderer(site: Site.load(from: root)).render(path: "/shop/mug/")
        #expect(html?.contains(#"<p class="price">$5</p>"#) == true)
    }
}
