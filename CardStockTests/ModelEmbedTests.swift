import Foundation
import Testing
@testable import CardStock

/// 3D models in pages: the `<!-- model … -->` line, the viewer, and the
/// bundled script, which goes only to sites that show a model.
struct ModelEmbedTests {
    let dir = FileManager.default.temporaryDirectory.appending(path: "cardstock-models-\(UUID().uuidString)")

    @Test func modelLines() {
        let line = ModelEmbed.marker(src: "/media/files/chair.glb", alt: "A walnut chair")
        #expect(line == #"<!-- model /media/files/chair.glb "A walnut chair" -->"#)
        let parsed = ModelEmbed.parse(line)
        #expect(parsed?.src == "/media/files/chair.glb" && parsed?.alt == "A walnut chair")
        // No description, any case and spacing, https links and .gltf.
        #expect(ModelEmbed.parse("<!--MODEL /media/a.gltf-->")?.alt == "3D model")
        #expect(ModelEmbed.parse("<!-- model https://example.com/a.glb?v=2 -->")?.src == "https://example.com/a.glb?v=2")
        // Not models, or not safe addresses.
        #expect(ModelEmbed.parse("<!-- model /media/a.jpg -->") == nil)
        #expect(ModelEmbed.parse("<!-- model http://example.com/a.glb -->") == nil)
        #expect(ModelEmbed.parse("<!-- model //example.com/a.glb -->") == nil)
        #expect(ModelEmbed.parse("<!-- model javascript:alert(1).glb -->") == nil)
        #expect(ModelEmbed.isModelFile("media/files/Chair.GLB"))
    }

    @Test func sizeBackgroundAndSpin() {
        var options = ModelEmbed.Options()
        options.width = 60
        options.height = 400
        options.background = .transparent
        options.spin = false
        let line = ModelEmbed.marker(src: "/media/chair.glb", alt: "Chair", options: options)
        #expect(line == #"<!-- model /media/chair.glb "Chair" width=60% height=400 background=transparent spin=off -->"#)
        #expect(ModelEmbed.parse(line)?.options == options)
        // Defaults aren't written.
        #expect(ModelEmbed.marker(src: "/media/chair.glb", alt: "Chair") == #"<!-- model /media/chair.glb "Chair" -->"#)
        // Settings without a description, a color, and values kept in range.
        let parsed = ModelEmbed.parse("<!-- model /media/a.glb width=5 height=9000px background=#AABBCC -->")
        #expect(parsed?.alt == "3D model" && parsed?.options.width == 10 && parsed?.options.height == 1200)
        #expect(parsed?.options.background == .color("#aabbcc"))
        // Anything but a color is ignored, so nothing else reaches the CSS.
        #expect(ModelEmbed.parse("<!-- model /media/a.glb background=red;x:y -->")?.options.background == .theme)
        #expect(ModelEmbed.Options.hexColor("#12345") == nil)

        let html = ModelEmbed.html(src: "/media/chair.glb", alt: "Chair", options: options)
        #expect(html.contains(#"<div class="model-embed" style="max-width: 60%">"#))
        #expect(html.contains(#"style="height: 400px; aspect-ratio: auto; background: transparent""#))
        #expect(!html.contains("auto-rotate"))
        #expect(ModelEmbed.html(src: "/a.glb", alt: "A").contains(#"auto-rotate auto-rotate-delay="1500""#))
        #expect(ModelEmbed.headHTML.contains("max-width: none !important"), "phones get the full width")
    }

    @Test func viewerInPages() {
        let markdown = """
        A chair.

        <!-- model /media/files/chair.glb "A <walnut> chair" -->

        ```
        <!-- model /media/files/code.glb -->
        ```
        """
        #expect(ModelEmbed.isUsed(in: markdown))
        let html = SiteRenderer.markdownToHTML(markdown)
        #expect(html.contains(#"<div class="model-embed"><model-viewer src="/media/files/chair.glb" alt="A &lt;walnut&gt; chair" camera-controls"#))
        #expect(html.contains(#"ar ar-modes="webxr scene-viewer quick-look""#))
        #expect(!html.contains(#"src="/media/files/code.glb""#), "lines in code blocks stay text")
    }

    @Test func copyMarkdownForAModel() {
        let file = MediaFile(path: "media/files/walnut-chair.glb", smallPath: nil, size: 10, added: .now, usedIn: [])
        #expect(MediaLibrary.markdown(for: file).hasPrefix("<!-- model /media/files/walnut-chair.glb"))
        #expect(MediaLibrary.referencedPaths(in: MediaLibrary.markdown(for: file)) == ["media/files/walnut-chair.glb"])
        #expect(FileFilter.apply([file], filter: .models, sort: .name, query: "").count == 1)
    }

    @Test func scriptOnlyWhereNeeded() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = dir.appending(path: "Site")
        try StarterSite.create(at: root, title: "Site")
        try "---\ntitle: Chair\n---\n\(ModelEmbed.marker(src: "/media/files/chair.glb", alt: "Chair"))\n".write(
            to: root.appending(path: "pages/chair.md"), atomically: true, encoding: .utf8)
        let site = try Site.load(from: root)
        let renderer = try SiteRenderer(site: site)

        let chair = try #require(renderer.render(path: "/pages/chair/"))
        let head = try #require(chair.range(of: "</head>"))
        let script = try #require(chair.range(of: #"<script type="module" src="/assets/cardstock/model-viewer.min.js"></script>"#))
        #expect(script.lowerBound < head.lowerBound, "in the head")
        #expect(!(renderer.render(path: "/pages/about/") ?? "").contains("model-viewer.min.js"))

        // Building copies the bundled viewer in.
        _ = try SiteBuilder.build(site)
        let built = root.appending(path: "public/assets/cardstock/model-viewer.min.js")
        let bundled = try #require(ModelEmbed.bundledScript)
        #expect(try Data(contentsOf: built) == Data(contentsOf: bundled))
    }

    @Test func noScriptWithoutModels() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = dir.appending(path: "Site")
        try StarterSite.create(at: root, title: "Site")
        _ = try SiteBuilder.build(try Site.load(from: root))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "public/assets/cardstock").path))
    }
}
