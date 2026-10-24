import Foundation
import Testing
@testable import CardStock

struct FrontMatterTests {
    @Test func parsesHeaderAndBody() {
        let text = """
        ---
        title: "Hello: world"
        date: 2026-10-20
        tags: [a, "b, c"]
        draft: true
        ---

        Body text.
        """
        let (fm, body) = FrontMatter.parse(text)
        #expect(fm.string("title") == "Hello: world")
        #expect(fm.string("date") == "2026-10-20")
        #expect(fm.list("tags") == ["a", "b, c"])
        #expect(fm.bool("draft"))
        #expect(body == "Body text.")
    }

    @Test func noHeaderKeepsWholeText() {
        let (fm, body) = FrontMatter.parse("Just text\n---\n")
        #expect(fm.entries.isEmpty)
        #expect(body == "Just text\n---\n")
    }

    @Test func roundTrips() {
        var fm = FrontMatter()
        fm["title"] = .string("Quote \" and: colon")
        fm["tags"] = .list(["x", "y, z"])
        fm["draft"] = .bool(false)
        fm["note"] = .string("true")
        let text = FrontMatter.serialize(fm, body: "Hi")
        let (parsed, body) = FrontMatter.parse(text)
        #expect(parsed == fm)
        #expect(body == "Hi\n")
    }

    @Test func keepsKeyOrderWhenEditing() {
        var (fm, _) = FrontMatter.parse("---\ntitle: A\ncustom: keep\ndate: 2026-01-01\n---\n")
        fm.setString("title", "B")
        #expect(fm.entries.map(\.key) == ["title", "custom", "date"])
        fm.setString("custom", "")
        #expect(fm.entries.map(\.key) == ["title", "date"])
    }
}

struct TemplateTests {
    @Test func rendersVariablesBlocksAndLoops() throws {
        let t = try Template("""
        <h1>{{ site.title }}</h1>{{{ html }}}\
        {{#each items}}[{{ name }}/{{ site.title }}]{{/each}}\
        {{#if missing}}yes{{else}}no{{/if}}{{#each tags}}#{{ this }}{{/each}}
        """)
        let out = t.render(.dict([
            "site": .dict(["title": .string("A&B")]),
            "html": .string("<b>x</b>"),
            "items": .list([.dict(["name": .string("one")]), .dict(["name": .string("two")])]),
            "tags": .list([.string("t1"), .string("t2")]),
        ]))
        #expect(out == "<h1>A&amp;B</h1><b>x</b>[one/A&amp;B][two/A&amp;B]no#t1#t2")
    }

    @Test func reportsUnclosedBlocks() {
        #expect(throws: TemplateError.self) { try Template("{{#if a}}x") }
        #expect(throws: TemplateError.self) { try Template("{{/each}}") }
        #expect(throws: TemplateError.self) { try Template("{{ a ") }
    }
}

struct SiteTests {
    @Test func slugify() {
        #expect(Site.slugify("Hello, World!") == "hello-world")
        #expect(Site.slugify("  Café crème  ") == "cafe-creme")
        #expect(Site.slugify("???") == "untitled")
    }

    @Test func buildsStarterSite() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "cardstock-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try StarterSite.create(at: root, title: "Test Site")

        var site = try Site.load(from: root)
        #expect(site.config.title == "Test Site")
        #expect(site.items(.post).count == 1)

        // Drafts are left out of the build.
        let draftURL = root.appending(path: "pages/secret.md")
        try "---\ntype: post\ntitle: Secret\ndate: 2026-02-01\ndraft: true\n---\nHidden".write(to: draftURL, atomically: true, encoding: .utf8)
        site = try Site.load(from: root)

        let report = try SiteBuilder.build(site)
        #expect(report.warnings.isEmpty)
        let pub = root.appending(path: "public")
        let fm = FileManager.default
        for file in ["index.html", "blog/pages/hello-world/index.html", "pages/about/index.html", "404.html",
                     "blog/pages/notes/index.html", "blog/index.html", "pages/search/index.html", "feed.xml",
                     "assets/style.css", "robots.txt"] {
            #expect(fm.fileExists(atPath: pub.appending(path: file).path), "missing \(file)")
        }
        #expect(!fm.fileExists(atPath: pub.appending(path: "blog/pages/secret").path))

        let home = try String(contentsOf: pub.appending(path: "index.html"), encoding: .utf8)
        #expect(home.contains("<title>Test Site</title>"))
        // The Home page's text sits above the post list; no stray /index/ page.
        #expect(home.contains("This is the Home page"))
        #expect(home.range(of: "This is the Home page")!.lowerBound < home.range(of: "post-list")!.lowerBound)
        #expect(!fm.fileExists(atPath: pub.appending(path: "index").path))
        #expect(home.contains("href=\"/blog/pages/hello-world/\""))
        let post = try String(contentsOf: pub.appending(path: "blog/pages/hello-world/index.html"), encoding: .utf8)
        #expect(post.contains("<strong>Markdown</strong>"))
        #expect(post.contains("<title>Hello, world · Test Site</title>"))
    }

    @Test func themeSettingsAreInjected() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "cardstock-theme-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try StarterSite.create(at: root, title: "Themed")

        // No theme.json: pages use the theme's CSS untouched.
        var site = try Site.load(from: root)
        #expect(site.theme == nil)
        var html = try SiteRenderer(site: site).render(path: "/") ?? ""
        #expect(!html.contains("cardstock-theme"))

        var theme = ThemeSettings()
        theme.bodyFont = "lora"
        theme.appearance = .dark
        theme.dark.accent = "#ff0000"
        theme.radius = 0
        theme.h1Size = 48
        try theme.save(to: root)
        site = try Site.load(from: root)
        #expect(site.theme == theme)

        html = try SiteRenderer(site: site).render(path: "/") ?? ""
        let style = try #require(html.range(of: "<style id=\"cardstock-theme\">"))
        let head = try #require(html.range(of: "</head>"))
        #expect(style.lowerBound < head.lowerBound)
        #expect(html.contains("--accent: #ff0000;"))
        #expect(html.contains("--radius: 0px;"))
        #expect(html.contains("--h1-size: 48px;"))
        #expect(html.contains("color-scheme: dark;"))
        #expect(!html.contains("prefers-color-scheme"))
        #expect(html.contains("fonts.googleapis.com/css2?family=Lora:"))
        #expect(html.contains("--font-body: \"Lora\", Georgia, serif;"))
    }

    @Test func webFontParsing() throws {
        let tag = #"<link href="https://fonts.googleapis.com/css2?family=Roboto&amp;family=Lora:ital@1&amp;display=swap" rel="stylesheet">"#
        #expect(WebFontLookup.extractURL(from: tag)?.absoluteString
                == "https://fonts.googleapis.com/css2?family=Roboto&family=Lora:ital@1&display=swap")
        #expect(WebFontLookup.extractURL(from: "@import url('https://use.typekit.net/abc.css');")?.absoluteString
                == "https://use.typekit.net/abc.css")
        #expect(WebFontLookup.extractURL(from: "not a link") == nil)

        let css = """
        @font-face { font-family: 'Roboto'; src: url(a.woff2); }
        @font-face { font-family: "Roboto"; font-weight: 700; }
        @font-face{font-family:proxima-nova;src:url(b)}
        """
        #expect(WebFontLookup.families(inCSS: css) == ["Roboto", "proxima-nova"])
        #expect(WebFontLookup.familyName(fromFile: URL(string: "https://x.com/f/Recoleta-Bold.woff2")!) == "Recoleta Bold")
    }

    @Test func customFontsRender() throws {
        var theme = ThemeSettings()
        theme.customFonts = [
            .init(family: "Recoleta", url: "https://cdn.example.com/Recoleta.woff2", style: .serif),
            .init(family: "Roboto", url: "https://fonts.googleapis.com/css2?family=Roboto&display=swap", style: .sans),
            .init(family: "Unused", url: "https://example.com/unused.css", style: .sans),
        ]
        theme.bodyFont = "custom:Roboto"
        theme.headingFont = "custom:Recoleta"
        let head = theme.headHTML
        #expect(head.contains(#"<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Roboto&amp;display=swap">"#))
        #expect(head.contains(#"src: url("https://cdn.example.com/Recoleta.woff2") format("woff2");"#))
        #expect(head.contains(#"--font-body: "Roboto", system-ui, sans-serif;"#))
        #expect(head.contains(#"--font-heading: "Recoleta", Georgia, serif;"#))
        #expect(!head.contains("unused.css"))

        let data = try JSONEncoder().encode(theme)
        #expect(try JSONDecoder().decode(ThemeSettings.self, from: data) == theme)
    }

    @Test func styleLibrarySavesExportsAndImports() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "cardstock-lib-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let library = StyleLibrary(folder: dir.appending(path: "Themes"))

        var theme = ThemeSettings()
        theme.light.accent = "#123456"
        let set = SavedStyle(name: "Ocean", theme: theme)
        try library.save(set)
        try library.save(SavedStyle(name: "Autumn", theme: ThemeSettings()))
        #expect(library.load().map(\.name) == ["Autumn", "Ocean"])

        // Export and import round trip.
        let file = dir.appending(path: "Ocean.cardstockstyle")
        try StyleLibrary.exportData(set).write(to: file)
        let imported = try StyleLibrary.importSet(from: file)
        #expect(imported.name == "Ocean")
        #expect(imported.theme == theme)
        #expect(imported.id != set.id)

        // A site's theme.json imports too, named after the site folder.
        let site = dir.appending(path: "My Blog/theme")
        try FileManager.default.createDirectory(at: site, withIntermediateDirectories: true)
        try theme.save(to: site.deletingLastPathComponent())
        #expect(try StyleLibrary.importSet(from: site.appending(path: "theme.json")).name == "My Blog")

        // Unrelated JSON is rejected.
        let junk = dir.appending(path: "junk.json")
        try Data(#"{"hello": 1}"#.utf8).write(to: junk)
        #expect(throws: SiteError.self) { try StyleLibrary.importSet(from: junk) }

        try library.delete(set.id)
        #expect(library.load().map(\.name) == ["Autumn"])
        #expect(StyleLibrary.uniqueName("autumn", existing: library.load()) == "autumn 2")
    }

    @Test func newSitesGetAProjectFile() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Field Notes \(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: root) }
        try StarterSite.create(at: root, title: "Field Notes")
        let file = try #require(ProjectSettings.projectFile(in: root))
        #expect(file.lastPathComponent == "\(root.lastPathComponent).cardstock")
        #expect(ProjectSettings.load(from: root) == ProjectSettings())

        // Saving the GitHub link updates the same file.
        try ProjectSettings(github: .init(repo: "me/notes", branch: "main")).save(to: root)
        #expect(ProjectSettings.projectFile(in: root) == file)
        #expect(ProjectSettings.load(from: root).github?.repo == "me/notes")
    }

    @Test func oldCardstockJsonMovesIntoProjectFile() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "legacy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(#"{"github": {"branch": "main", "repo": "me/old"}}"#.utf8)
            .write(to: root.appending(path: "cardstock.json"))
        #expect(ProjectSettings.load(from: root).github?.repo == "me/old")

        let file = try ProjectSettings.ensureProjectFile(in: root)
        #expect(file.pathExtension == "cardstock")
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "cardstock.json").path))
        #expect(ProjectSettings.load(from: root).github?.repo == "me/old")
    }

    @MainActor
    @Test func identicalStylesCanBeToggled() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "cardstock-styles-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = dir.appending(path: "Site")
        try StarterSite.create(at: root, title: "Site")
        let model = AppModel(styleLibrary: StyleLibrary(folder: dir.appending(path: "Styles")))
        model.open(root)
        #expect(model.isUsingDefaultStyle)

        // A saved style with the same settings as the default.
        model.saveCurrentStyle(as: "Look")
        let look = try #require(model.styles.first)
        #expect(model.activeStyle?.id == look.id)

        model.applyDefaultStyle()
        #expect(model.isUsingDefaultStyle)
        #expect(model.activeStyle == nil)

        model.applyStyle(look)
        #expect(model.activeStyle?.id == look.id)
        #expect(!model.isUsingDefaultStyle)

        // Editing makes an unsaved style, which survives switching away.
        var custom = model.currentTheme
        custom.radius = 20
        model.updateTheme(custom)
        #expect(model.activeStyle == nil && !model.isUsingDefaultStyle)
        model.applyDefaultStyle()
        #expect(model.unsavedStyleTheme == custom)
        model.applyUnsavedStyle()
        #expect(model.currentTheme == custom)
        #expect(model.unsavedStyleTheme == custom)
        model.saveNow()
    }

    @Test func versionComparison() {
        #expect(AppInfo.isNewer("0.2.0", than: "0.1.0"))
        #expect(AppInfo.isNewer("v1.10", than: "1.9.2"))
        #expect(!AppInfo.isNewer("0.1.0", than: "0.1.0"))
        #expect(!AppInfo.isNewer("0.1", than: "0.1.0"))
        #expect(!AppInfo.isNewer("0.0.9", than: "0.1.0"))
    }

    @MainActor
    @Test func webFontsLiveWithTheSite() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "cardstock-fonts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = dir.appending(path: "Site")
        try StarterSite.create(at: root, title: "Site")

        // An older site with a web font stored inside theme.json.
        let roboto = ThemeSettings.CustomFont(family: "Roboto", url: "https://fonts.googleapis.com/css2?family=Roboto", style: .sans)
        var old = ThemeSettings()
        old.customFonts = [roboto]
        old.bodyFont = roboto.id
        try old.save(to: root)

        let model = AppModel(styleLibrary: StyleLibrary(folder: dir.appending(path: "Styles")))
        model.open(root)
        // Moved into theme/fonts.json; theme.json keeps only the look.
        #expect(model.webFonts == [roboto])
        #expect(Site.loadWebFonts(from: root) == [roboto])
        #expect(ThemeSettings.load(from: root)?.customFonts.isEmpty == true)
        #expect(ThemeSettings.load(from: root)?.bodyFont == roboto.id)

        // Pages still load it.
        let site = try Site.load(from: root)
        let html = try SiteRenderer(site: site).render(path: "/") ?? ""
        #expect(html.contains("family=Roboto"))

        // A saved style carries the font; switching styles keeps the site's fonts.
        model.saveCurrentStyle(as: "Roboto Look")
        let style = try #require(model.styles.first)
        #expect(style.theme.customFonts == [roboto])
        #expect(model.activeStyle?.id == style.id)
        model.applyDefaultStyle()
        #expect(model.webFonts == [roboto])

        // Using the style on another site brings its font along.
        let other = dir.appending(path: "Other")
        try StarterSite.create(at: other, title: "Other")
        model.open(other)
        #expect(model.webFonts.isEmpty)
        model.applyStyle(style)
        #expect(model.webFonts == [roboto])
        #expect(model.activeStyle?.id == style.id)
        #expect(Site.loadWebFonts(from: other) == [roboto])

        model.removeWebFont(roboto)
        #expect(model.webFonts.isEmpty)
        #expect(model.currentTheme.bodyFont == ThemeSettings().bodyFont)
        model.saveNow()
    }

    @Test func fontToastWording() {
        #expect(AddWebFontSheet.message(for: ["Roboto"]) == "“Roboto” added to the font menus.")
        #expect(AddWebFontSheet.message(for: ["A", "B"]) == "“A” and “B” added to the font menus.")
        #expect(AddWebFontSheet.message(for: ["A", "B", "C"]) == "“A”, “B” and “C” added to the font menus.")
    }

    @MainActor
    @Test func homePageIsCreatedAndStartScreenOpens() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "cardstock-home-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = dir.appending(path: "Site")
        try StarterSite.create(at: root, title: "Site")
        // Simulate a site made before Home pages existed.
        try FileManager.default.removeItem(at: root.appending(path: "pages/index.md"))

        let model = AppModel(styleLibrary: StyleLibrary(folder: dir.appending(path: "Styles")))
        model.open(root)
        let home = try #require(model.site?.home)
        #expect(home.title == "Home")
        #expect(home.path == "/")
        // Sites open on the Start screen.
        #expect(model.selection == .start)
        #expect(model.site?.items(.page).first?.isHome == true)

        // New pages can't take Home's file name.
        model.newItem(.page, title: "Index")
        #expect(model.selectedPage?.slug == "index-2")
        // New pages open in the Pages view's editor column.
        #expect(model.selection == .pages)
    }
}

struct GoogleFontsLinkTests {
    @Test func shareAndSpecimenLinksBecomeStylesheets() throws {
        let share = try #require(URL(string: "https://fonts.google.com/share?selection.family=Open+Sans:ital,wght@0,300..800;1,300..800%7CTitillium+Web:wght@400;700"))
        #expect(WebFontLookup.stylesheetURL(for: share).absoluteString
                == "https://fonts.googleapis.com/css2?family=Open+Sans:ital,wght@0,300..800;1,300..800&family=Titillium+Web:wght@400;700&display=swap")
        let specimen = try #require(URL(string: "https://fonts.google.com/specimen/Space+Grotesk"))
        #expect(WebFontLookup.stylesheetURL(for: specimen).absoluteString
                == "https://fonts.googleapis.com/css2?family=Space+Grotesk&display=swap")
        let css = try #require(URL(string: "https://fonts.googleapis.com/css2?family=Lora&display=swap"))
        #expect(WebFontLookup.stylesheetURL(for: css) == css)
    }
}
