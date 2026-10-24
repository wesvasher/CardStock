import Foundation
import Testing
@testable import CardStock

struct CollectionTests {
    let dir = FileManager.default.temporaryDirectory.appending(path: "cardstock-collections-\(UUID().uuidString)")

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

    /// The starter site plus a portfolio and a videos collection.
    private func siteWithCollections() throws -> URL {
        let root = try starter()
        var site = try Site.load(from: root)
        var portfolio = ContentCollection(preset: .portfolio, id: "work", name: "Work")
        portfolio.listCategories = true
        site.config.collections += [portfolio, ContentCollection(preset: .videos, id: "videos")]
        try site.saveConfig()
        try write("---\ntype: collection\ntitle: Selected Work\n---\nThings I made.", "pages/work.md", in: root)
        try write("---\ntype: work\ntitle: Bridge\ndate: 2025-01-01\ncover: /media/bridge.jpg\ntags: [Steel, design]\ncategories: [big]\n---\nA bridge.", "pages/bridge.md", in: root)
        try write("---\ntype: work\ntitle: Chair\ndate: 2026-02-01\ntags: [Design]\n---\nA chair.", "pages/chair.md", in: root)
        try write("---\ntype: work\ntitle: Secret\ndate: 2026-03-01\ndraft: true\ntags: [hidden]\n---\n", "pages/secret.md", in: root)
        try write("---\ntype: work-category\ntitle: Big Things\n---\nLarge pieces.", "pages/big.md", in: root)
        try write("---\ntype: videos\ntitle: Launch\ndate: 2026-04-01\nvideo: https://youtu.be/abc_DEF-123\n---\nWatch it.", "pages/launch.md", in: root)
        return root
    }

    @Test func typesAndAddresses() {
        #expect(ContentKind(rawValue: "post") == .post && ContentKind.post.rawValue == "post")
        #expect(ContentKind(rawValue: "work") == .item("work") && ContentKind.item("work").rawValue == "work")
        #expect(ContentKind(rawValue: "work-category") == .category("work"))
        #expect(ContentKind(rawValue: "collection") == nil)
        #expect(ContentKind(rawValue: "collection", slug: "work") == .main("work"))
        #expect(ContentKind(rawValue: "Not a type!") == nil)

        #expect(ContentKind.post.path(for: "hi") == "/posts/hi/")
        #expect(ContentKind.blogCategory.path(for: "travel") == "/blog/travel/")
        #expect(ContentKind.product.path(for: "mug") == "/shop/mug/")
        #expect(ContentKind.item("work").path(for: "bridge") == "/work/bridge/")
        #expect(ContentKind.main("work").path(for: "work") == "/work/")

        let main = ContentItem(fileURL: URL(filePath: "/s/pages/work.md"), text: "---\ntype: collection\ntitle: Work\n---\n")
        #expect(main.kind == .main("work") && main.path == "/work/" && !main.canBeDeleted && main.isListedOnTagPages)
    }

    @Test func sitesWithoutCollectionsGetDefaults() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = try starter()
        // Like a site from before collections: no "collections" in site.json.
        let url = root.appending(path: "site.json")
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        json["collections"] = nil
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        #expect(try Site.load(from: root).config.collections.map(\.id) == ["blog"])

        try write("---\ntype: product\ntitle: Mug\n---\n", "pages/mug.md", in: root)
        var site = try Site.load(from: root)
        #expect(site.config.collections.map(\.id) == ["blog", "shop"])
        #expect(site.config.collection("shop")?.selling == true)
        // Saved with the next change.
        try site.saveConfig()
        let saved = try String(contentsOf: url, encoding: .utf8)
        #expect(saved.contains(#""collections""#) && saved.contains(#""itemName" : "Product""#))
        site = try Site.load(from: root)
        #expect(site.config.collections.map(\.id) == ["blog", "shop"])
    }

    @Test func missingSettingsComeFromThePreset() throws {
        let json = #"{ "id": "work", "preset": "portfolio", "name": "Work" }"#
        let c = try JSONDecoder().decode(ContentCollection.self, from: Data(json.utf8))
        #expect(c.name == "Work" && c.itemName == "Project" && c.listStyle == .gallery && c.dated)
        let blog = try JSONDecoder().decode(ContentCollection.self, from: Data(#"{ "id": "blog" }"#.utf8))
        #expect(blog.preset == .blog && blog.onHome && blog.inFeed)
    }

    @Test func mainCategoryAndItemPages() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = try siteWithCollections()
        let renderer = try SiteRenderer(site: Site.load(from: root))
        let paths = renderer.paths
        #expect(paths.contains("/work/") && paths.contains("/work/bridge/") && paths.contains("/work/big/"))
        #expect(paths.contains("/videos/") && paths.contains("/videos/launch/"))
        #expect(!paths.contains("/work/secret/"))

        // The main page: its own title and text, then a gallery, newest first.
        let work = try #require(renderer.render(path: "/work/"))
        #expect(work.contains("Selected Work") && work.contains("Things I made."))
        #expect(work.contains(#"class="collection-grid collection-gallery" style="--cols:3""#))
        #expect(work.contains(#"<img src="/media/bridge.jpg""#) && !work.contains("Secret"))
        let chair = try #require(work.range(of: "Chair")), bridge = try #require(work.range(of: "Bridge"))
        #expect(chair.lowerBound < bridge.lowerBound)
        // Links to the categories, with the page you're on marked.
        #expect(work.contains(#"<ul class="category-links"><li><a href="/work/" aria-current="page">All</a></li><li><a href="/work/big/">Big Things</a></li></ul>"#))
        #expect(work.contains(".collection-grid {"))

        let big = try #require(renderer.render(path: "/work/big/"))
        #expect(big.contains("Large pieces.") && big.contains(#"href="/work/bridge/""#) && !big.contains(#"href="/work/chair/""#))
        #expect(big.contains(#"<a href="/work/big/" aria-current="page">Big Things</a>"#))

        // An item: no date (the preset hides it), categories, tags as links, a pager.
        let page = try #require(renderer.render(path: "/work/bridge/"))
        #expect(page.contains(#"<a class="category" href="/work/big/">Big Things</a>"#))
        #expect(page.contains(#"<a class="tag" href="/tags/steel/">Steel</a>"#))
        #expect(!page.contains("<time"))
        #expect(page.contains(#"<a class="prev" href="/work/chair/"><small>Newer</small>Chair</a>"#))
        #expect(page.contains(#"<a class="all" href="/work/">All projects</a>"#))
        #expect(page.contains(#"<img class="cover" src="/media/bridge.jpg""#))

        // A video item: the player, and its thumbnail in lists.
        let launch = try #require(renderer.render(path: "/videos/launch/"))
        #expect(launch.contains(#"<iframe src="https://www.youtube-nocookie.com/embed/abc_DEF-123""#))
        let videos = try #require(renderer.render(path: "/videos/"))
        #expect(videos.contains("https://i.ytimg.com/vi/abc_DEF-123/hqdefault.jpg"))
    }

    @Test func settingsChangeWhatPagesShow() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = try siteWithCollections()
        var site = try Site.load(from: root)
        let i = try #require(site.config.collections.firstIndex { $0.id == "work" })
        site.config.collections[i].listStyle = .list
        site.config.collections[i].listDates = true
        site.config.collections[i].sort = .title
        site.config.collections[i].showTags = false
        site.config.collections[i].prevNext = false
        site.config.collections[i].showDate = true
        site.config.collections[i].onHome = true
        site.config.collections[i].emptyText = "Nothing yet."
        try site.saveConfig()
        let renderer = try SiteRenderer(site: Site.load(from: root))

        let work = try #require(renderer.render(path: "/work/"))
        #expect(work.contains(#"<ul class="post-list"><li><a href="/work/bridge/">Bridge</a> <time datetime="2025-01-01">"#))
        let page = try #require(renderer.render(path: "/work/bridge/"))
        #expect(!page.contains(#"class="tag""#) && !page.contains(#"class="pager""#) && page.contains(#"<time datetime="2025-01-01">"#))
        // Home lists the blog's posts and the work, newest first.
        let home = try #require(renderer.render(path: "/"))
        #expect(home.contains(#"href="/work/chair/""#) && home.contains(#"href="/posts/hello-world/""#))

        // A category with nothing in it shows the collection's empty text.
        try write("---\ntype: work-category\ntitle: Empty\n---\n", "pages/empty.md", in: root)
        let empty = try SiteRenderer(site: Site.load(from: root)).render(path: "/work/empty/")
        #expect(empty?.contains(#"<p class="empty">Nothing yet.</p>"#) == true)
    }

    @Test func videoLinks() {
        #expect(SiteRenderer.youTubeID("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10") == "dQw4w9WgXcQ")
        #expect(SiteRenderer.youTubeID("https://youtube.com/shorts/abc123") == "abc123")
        #expect(SiteRenderer.youTubeID("https://example.com/watch?v=x") == nil)
        #expect(SiteRenderer.videoEmbedHTML("https://vimeo.com/76979871").contains("https://player.vimeo.com/video/76979871"))
        #expect(SiteRenderer.videoEmbedHTML("/media/files/clip.mp4").contains(#"<video src="/media/files/clip.mp4" controls"#))
        #expect(SiteRenderer.videoEmbedHTML("https://example.com/page").contains(#"<a href="https://example.com/page">"#))
        #expect(SiteRenderer.videoEmbedHTML("  ").isEmpty)
    }

    @Test func tagsAndTagPages() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = try siteWithCollections()
        var site = try Site.load(from: root)
        site.config.tags.list = [.init(name: "Design", description: "Things about design."), .init(name: "Unused")]
        try site.saveConfig()
        site = try Site.load(from: root)

        // "design" and "Design" are one tag, named as site.json has it.
        let index = site.tagIndex()
        let design = try #require(index.first { $0.slug == "design" })
        #expect(design.name == "Design" && design.pages.count == 2 && design.description == "Things about design.")
        #expect(index.contains { $0.slug == "unused" && $0.pages.isEmpty })
        #expect(site.tagIndex(includeDrafts: false).first { $0.slug == "hidden" }?.pages.isEmpty ?? true)

        let renderer = try SiteRenderer(site: site)
        let paths = renderer.paths
        #expect(paths.contains("/tags/") && paths.contains("/tags/design/") && paths.contains("/tags/meta/"))
        #expect(!paths.contains("/tags/unused/") && !paths.contains("/tags/hidden/"))

        let page = try #require(renderer.render(path: "/tags/design/"))
        #expect(page.contains("<h1>Design</h1>") && page.contains("Things about design.") && page.contains("2 pages"))
        #expect(page.contains(#"href="/work/chair/""#) && page.contains(#"href="/work/bridge/""#))
        let all = try #require(renderer.render(path: "/tags/"))
        #expect(all.contains(#"<a href="/tags/steel/">Steel<small>1</small></a>"#) && !all.contains("Unused"))

        // Off: no tag pages, and tags are plain words.
        site.config.tags.pages = false
        let off = try SiteRenderer(site: site)
        #expect(!off.paths.contains { $0.hasPrefix("/tags/") } && off.render(path: "/tags/design/") == nil)
        #expect(off.render(path: "/posts/hello-world/")?.contains(#"<span class="tag">meta</span>"#) == true)
    }

    @Test func renamingAndMergingTags() {
        let item = ContentItem(fileURL: URL(filePath: "/s/pages/a.md"), text: "---\ntitle: A\ntags: [Swift, swiftui, Mac]\n---\n")
        #expect(item.hasTag("swiftui") && !item.hasTag("ios"))
        #expect(item.tags(renaming: "swiftui", to: "SwiftUI") == ["Swift", "SwiftUI", "Mac"])
        // Renaming to a tag it already has merges them.
        #expect(item.tags(renaming: "mac", to: "swift") == ["Swift", "swiftui"])

        var settings = TagSettings()
        settings.list = [.init(name: "Old", description: "Kept"), .init(name: "Target")]
        settings.rename("old", to: "target")
        #expect(settings.list.map(\.name) == ["target"] && settings.list[0].description == "Kept")
    }

    @Test func collectionAddressesAreChecked() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let site = try Site.load(from: try siteWithCollections())
        #expect(ContentCollection.problem(withID: "recipes", in: site) == nil)
        #expect(ContentCollection.problem(withID: "work", in: site) != nil)
        #expect(ContentCollection.problem(withID: "posts", in: site) != nil)
        #expect(ContentCollection.problem(withID: "about", in: site) != nil)
        #expect(ContentCollection.problem(withID: "tags", in: site) != nil)
        #expect(ContentCollection.problem(withID: "My Stuff", in: site) != nil)
        #expect(site.unavailableSlugs.contains("work") && site.unavailableSlugs.contains("videos"))
        #expect(site.config.kinds.contains(.item("work")) && site.config.singularName(.item("work")) == "Project")
    }

    @Test func filesAndEveryPageCanBeTagged() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = try siteWithCollections()
        let fm = FileManager.default
        try fm.createDirectory(at: root.appending(path: "media/files"), withIntermediateDirectories: true)
        for name in ["beach.jpg", "beach-small.jpg", "menu.pdf", "gone.jpg"] {
            try Data([0]).write(to: root.appending(path: "media/files/\(name)"))
        }
        var tags = MediaTags()
        tags["media/files/beach.jpg"] = ["design", "Travel"]
        tags["media/files/menu.pdf"] = ["Design"]
        tags["media/files/gone.jpg"] = ["design"]
        try tags.save(to: root)
        try fm.removeItem(at: root.appending(path: "media/files/gone.jpg"))
        // Home and link menus can have tags too.
        try write("---\ntitle: Home\ntags: [Travel]\n---\nHi", "pages/index.md", in: root)
        try write("---\ntype: links\ntitle: Social\ntags: [Travel]\n---\n", "pages/social.md", in: root)

        var site = try Site.load(from: root)
        #expect(site.mediaTags["media/files/beach.jpg"] == ["design", "Travel"])
        let design = try #require(site.tagIndex().first { $0.slug == "design" })
        #expect(design.files == ["media/files/beach.jpg", "media/files/menu.pdf"] && design.usage == "2 pages · 2 files")
        let travel = try #require(site.tagIndex().first { $0.slug == "travel" })
        #expect(travel.pages.count == 2 && travel.files == ["media/files/beach.jpg"])
        #expect(MediaLibrary.scan(site).first { $0.path == "media/files/beach.jpg" }?.tags == ["design", "Travel"])

        // The tag page: Home (not the link menu), then the photo (its small
        // version, linking to the large one), then other files.
        let renderer = try SiteRenderer(site: site)
        #expect(renderer.paths.contains("/tags/travel/"))
        let page = try #require(renderer.render(path: "/tags/travel/"))
        #expect(page.contains(#"href="/""#) && !page.contains("Social") && page.contains("1 page · 1 file"))
        #expect(page.contains(#"<a class="gallery-item" href="/media/files/beach.jpg"><img src="/media/files/beach-small.jpg""#))
        let designPage = try #require(renderer.render(path: "/tags/design/"))
        #expect(designPage.contains(#"<h2 class="tag-heading">Files</h2>"#) && designPage.contains(#"href="/media/files/menu.pdf">menu.pdf</a>"#))

        // A tag only on files still gets a page.
        site.mediaTags["media/files/menu.pdf"] = ["Recipes"]
        #expect(try SiteRenderer(site: site).paths.contains("/tags/recipes/"))

        // Renaming and removing reach file tags; saving drops files that are gone.
        site.mediaTags.rename("design", to: "Graphic Design")
        site.mediaTags.remove("travel")
        #expect(site.mediaTags["media/files/beach.jpg"] == ["Graphic Design"])
        try site.mediaTags.save(to: root)
        let saved = try String(contentsOf: root.appending(path: MediaTags.fileName), encoding: .utf8)
        #expect(saved.contains("Graphic Design") && !saved.contains("gone.jpg"))
        #expect(TagSettings.changing(["a", "B"], adding: ["b", "c"], removing: ["A"]) == ["B", "c"])
        // Nothing tagged: no media.json.
        try MediaTags().save(to: root)
        #expect(!fm.fileExists(atPath: root.appending(path: MediaTags.fileName).path))
    }
}
