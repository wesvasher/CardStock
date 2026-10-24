import Foundation
import Testing
@testable import CardStock

struct FolderTests {
    let dir = FileManager.default.temporaryDirectory.appending(path: "cardstock-folders-\(UUID().uuidString)")

    private func site() throws -> Site {
        let root = dir.appending(path: "Site")
        try StarterSite.create(at: root, title: "Site")
        try "---\ntitle: Subscribe\n---\nJoin the list.".write(to: root.appending(path: "pages/subscribe.md"), atomically: true, encoding: .utf8)
        try "---\ntitle: Secret\ndraft: true\n---\n".write(to: root.appending(path: "pages/secret.md"), atomically: true, encoding: .utf8)
        var site = try Site.load(from: root)
        site.config.url = "https://example.com"
        site.config.folders = [Folder(name: "subscribe", page: "subscribe"), Folder(name: "hush", page: "secret"),
                               Folder(name: "posts", page: "blog"), Folder(name: "lost", page: "gone")]
        try site.saveConfig()
        return try Site.load(from: root)
    }

    @Test func folderShowsItsPage() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let site = try site()
        #expect(site.config.folders.count == 4)
        let renderer = try SiteRenderer(site: site)
        let paths = renderer.paths
        // The page keeps its own address; the folder is a second one.
        #expect(paths.contains("/pages/subscribe/") && paths.contains("/subscribe/"))
        // A collection's main page works too; drafts and missing pages don't.
        #expect(paths.contains("/posts/") && !paths.contains("/hush/") && !paths.contains("/lost/"))
        let html = try #require(renderer.render(path: "/subscribe/"))
        #expect(html.contains("Join the list.") && html.contains(#"<link rel="canonical" href="https://example.com/pages/subscribe/">"#))
        #expect(renderer.render(path: "/subscribe/index.html") != nil && renderer.render(path: "/hush/") == nil)
        #expect(try SiteRenderer(site: site, includeDrafts: true).render(path: "/hush/") != nil)

        #expect(SiteInsights.linkStatus("/subscribe/", in: site) == .ok)
        #expect(SiteInsights.linkStatus("/hush", in: site) == .draft)
        #expect(SiteInsights.linkStatus("/lost/", in: site) == .missing)
        let check = SiteInsights.healthChecks(site, files: [], outdatedThemeFiles: []).first { $0.id == "folders" }
        #expect(check?.problems.count == 1)

        // Built as its own folder.
        _ = try SiteBuilder.build(site)
        #expect(FileManager.default.fileExists(atPath: site.root.appending(path: "public/subscribe/index.html").path))
    }

    @Test func namesAreChecked() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = try site().config
        #expect(config.folderProblem("contact") == nil)
        #expect(config.folderProblem("blog") != nil, "a collection's folder")
        #expect(config.folderProblem("pages") != nil && config.folderProblem("media") != nil && config.folderProblem("tags") != nil)
        #expect(config.folderProblem("subscribe") != nil, "already yours")
        #expect(config.folderProblem("subscribe", except: "subscribe") == nil)
        #expect(config.folderProblem("Sign Up") != nil && config.folderProblem("") != nil && config.folderProblem("search") != nil)
        #expect(config.systemFolders.map(\.name) == ["blog", "pages", "tags", "media", "assets"])
        // A collection can't take a folder's name.
        #expect(ContentCollection.problem(withID: "subscribe", in: try Site.load(from: dir.appending(path: "Site"))) != nil)
    }
}
