import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CardStock

struct SiteIconTests {
    let dir = FileManager.default.temporaryDirectory.appending(path: "cardstock-icon-\(UUID().uuidString)")

    /// A transparent 600 × 300 PNG with a red square in the middle.
    private func writeImage(to url: URL) throws {
        let context = CGContext(data: nil, width: 600, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 250, y: 100, width: 100, height: 100))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try SiteIcon.pngData(context.makeImage()!)!.write(to: url)
    }

    private func site() throws -> Site {
        let root = dir.appending(path: "Site")
        if !FileManager.default.fileExists(atPath: root.path) { try StarterSite.create(at: root, title: "Field Notes") }
        return try Site.load(from: root)
    }

    @Test func headTags() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        var site = try site()
        // No icon: nothing added.
        #expect(!(try SiteRenderer(site: site).render(path: "/") ?? "").contains("apple-touch-icon"))

        site.config.icon.image = "/media/files/icon.png"
        var html = try SiteRenderer(site: site).render(path: "/pages/about/") ?? ""
        #expect(html.contains("<link rel=\"icon\" href=\"/favicon-32.png\" sizes=\"32x32\" type=\"image/png\">"))
        #expect(html.contains("<link rel=\"apple-touch-icon\" href=\"/apple-touch-icon.png\">"))
        #expect(html.contains("<meta name=\"apple-mobile-web-app-title\" content=\"Field Notes\">"))
        #expect(html.contains("<link rel=\"manifest\" href=\"/site.webmanifest\">"))

        // A custom favicon is linked as it is; turned off, it's ignored.
        site.config.icon.favicon = "/media/files/spin.gif"
        #expect((try SiteRenderer(site: site).render(path: "/") ?? "").contains("favicon-32.png"))
        site.config.icon.customFavicon = true
        site.config.icon.name = "Notes"
        html = try SiteRenderer(site: site).render(path: "/") ?? ""
        #expect(html.contains("<link rel=\"icon\" href=\"/media/files/spin.gif\" type=\"image/gif\">"))
        #expect(!html.contains("favicon-32.png"))
        #expect(html.contains("content=\"Notes\""))

        // Just a favicon, no site icon: no home screen tags.
        site.config.icon.image = ""
        html = try SiteRenderer(site: site).render(path: "/") ?? ""
        #expect(html.contains("spin.gif"))
        #expect(!html.contains("apple-touch-icon"))
        #expect(!html.contains("manifest"))
    }

    @Test func settingsDecodeWithDefaults() throws {
        let config = try JSONDecoder().decode(SiteConfig.self, from: Data(#"{"title":"A","icon":{"image":"/media/files/i.png"}}"#.utf8))
        #expect(config.icon.image == "/media/files/i.png")
        #expect(config.icon.background == "#ffffff")
        #expect(!config.icon.customFavicon)
        let old = try JSONDecoder().decode(SiteConfig.self, from: Data(#"{"title":"A"}"#.utf8))
        #expect(!old.icon.isSet)
    }

    @Test func manifest() throws {
        var config = SiteConfig()
        config.title = "Field Notes"
        config.icon.image = "/media/files/icon.png"
        config.icon.background = "#112233"
        config.icon.name = "Notes"
        let json = try JSONSerialization.jsonObject(with: Data(SiteIcon.manifest(config).utf8)) as! [String: Any]
        #expect(json["name"] as? String == "Field Notes")
        #expect(json["short_name"] as? String == "Notes")
        #expect(json["background_color"] as? String == "#112233")
        let icons = json["icons"] as! [[String: String]]
        #expect(icons.map { $0["src"]! } == ["/icon-192.png", "/icon-512.png", "/icon-maskable-512.png"])
        #expect(icons.last?["purpose"] == "maskable")
    }

    @Test func buildWritesIcons() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        var site = try site()
        try writeImage(to: site.root.appending(path: "media/files/icon.png"))
        site.config.icon.image = "/media/files/icon.png"
        site.config.icon.background = "#0000ff"
        let report = try SiteBuilder.build(site)
        let out = site.root.appending(path: "public")
        for file in ["apple-touch-icon.png", "icon-192.png", "icon-512.png", "icon-maskable-512.png", "favicon-32.png", "site.webmanifest"] {
            #expect(FileManager.default.fileExists(atPath: out.appending(path: file).path), "\(file)")
        }
        #expect(ImageImporter.pixelSize(of: out.appending(path: "apple-touch-icon.png"))! == (180, 180))
        #expect(ImageImporter.pixelSize(of: out.appending(path: "icon-maskable-512.png"))! == (512, 512))
        // A small image gets a warning.
        #expect(report.warnings.contains { $0.contains("600 × 300") })

        // The touch icon is filled with the background in its corners.
        let source = CGImageSourceCreateWithURL(out.appending(path: "apple-touch-icon.png") as CFURL, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        // The bottom-left pixel (r, g, b, a).
        #expect(pixel[0] < 10 && pixel[2] > 245 && pixel[3] == 255)

        // A custom favicon skips the made one; a missing icon only warns.
        site.config.icon.customFavicon = true
        site.config.icon.favicon = "/media/files/missing.gif"
        site.config.icon.image = "/media/files/nope.png"
        let second = try SiteBuilder.build(site)
        #expect(!FileManager.default.fileExists(atPath: out.appending(path: "favicon-32.png").path))
        #expect(second.warnings.contains { $0.contains("missing.gif") })
        #expect(second.warnings.contains { $0.contains("nope.png") })
    }
}
