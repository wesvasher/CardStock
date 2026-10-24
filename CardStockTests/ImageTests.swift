import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import CardStock

struct ImageTests {
    let dir = FileManager.default.temporaryDirectory.appending(path: "cardstock-images-\(UUID().uuidString)")

    /// Writes a solid-color test image, optionally with GPS metadata.
    private func makeImage(_ name: String, width: Int, height: Int, type: UTType = .jpeg, gps: Bool = false) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let url = dir.appending(path: name)
        let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        var props: [CFString: Any] = [:]
        if gps {
            props[kCGImagePropertyGPSDictionary] = [kCGImagePropertyGPSLatitude: 37.33, kCGImagePropertyGPSLatitudeRef: "N"]
        }
        CGImageDestinationAddImage(dest, context.makeImage()!, props as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
        return url
    }

    private func info(_ url: URL) -> (width: Int, height: Int, hasGPS: Bool) {
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]
        return (props[kCGImagePropertyPixelWidth] as! Int, props[kCGImagePropertyPixelHeight] as! Int,
                props[kCGImagePropertyGPSDictionary] != nil)
    }

    @Test func optimizesLargePhotos() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let photo = try makeImage("Beach Day.jpg", width: 4000, height: 3000, gps: true)
        #expect(info(photo).hasGPS)
        let folder = dir.appending(path: "media/posts/trip")

        let blocks = try ImageImporter.importImages([.init(source: photo, alt: "The [beach]")],
                                                    folder: folder, urlPrefix: "/media/posts/trip", mode: .optimized)
        #expect(blocks == ["[![The beach](/media/posts/trip/beach-day-small.jpg)](/media/posts/trip/beach-day.jpg)"])

        let large = info(folder.appending(path: "beach-day.jpg"))
        let small = info(folder.appending(path: "beach-day-small.jpg"))
        #expect(large.width == 2400 && large.height == 1800)
        #expect(small.width == 1200 && small.height == 900)
        #expect(!large.hasGPS && !small.hasGPS)

        // Same name again gets a new one rather than overwriting.
        let again = try ImageImporter.importImages([.init(source: photo, alt: "x")],
                                                   folder: folder, urlPrefix: "/m", mode: .optimized)
        #expect(again[0].contains("beach-day-2-small.jpg"))
    }

    @Test func smallImagesAndPNGsAndOriginals() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = dir.appending(path: "out")

        // Already small: one file, no lightbox link.
        let small = try makeImage("icon.jpg", width: 800, height: 600)
        var blocks = try ImageImporter.importImages([.init(source: small, alt: "Icon")],
                                                    folder: folder, urlPrefix: "/m", mode: .optimized)
        #expect(blocks == ["![Icon](/m/icon.jpg)"])

        // Screenshots stay PNG.
        let shot = try makeImage("Screen Shot.png", width: 3000, height: 2000, type: .png)
        blocks = try ImageImporter.importImages([.init(source: shot, alt: "Shot")],
                                                folder: folder, urlPrefix: "/m", mode: .optimized)
        #expect(blocks == ["[![Shot](/m/screen-shot-small.png)](/m/screen-shot.png)"])

        // Full resolution copies the original untouched.
        let photo = try makeImage("big.jpg", width: 5000, height: 2500, gps: true)
        blocks = try ImageImporter.importImages([.init(source: photo, alt: "Big")],
                                                folder: folder, urlPrefix: "/m", mode: .original)
        #expect(blocks == ["![Big](/m/big.jpg)"])
        #expect(try Data(contentsOf: folder.appending(path: "big.jpg")) == Data(contentsOf: photo))

        // HEIC is converted to a full-size JPEG even at full resolution.
        let heic = try makeImage("phone.heic", width: 3000, height: 2000, type: .heic)
        blocks = try ImageImporter.importImages([.init(source: heic, alt: "Phone")],
                                                folder: folder, urlPrefix: "/m", mode: .original)
        #expect(blocks == ["![Phone](/m/phone.jpg)"])
        #expect(info(folder.appending(path: "phone.jpg")).width == 3000)
    }

    @Test func lightboxIsAddedOnlyWhenNeeded() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = dir.appending(path: "Site")
        try StarterSite.create(at: root, title: "Site")
        let post = root.appending(path: "pages/hello-world.md")
        var text = try String(contentsOf: post, encoding: .utf8)

        var html = try SiteRenderer(site: Site.load(from: root)).render(path: "/posts/hello-world/") ?? ""
        #expect(!html.contains("cardstock-lightbox"))

        text += "\n[![A](/media/posts/hello-world/a-small.jpg)](/media/posts/hello-world/a.jpg)\n"
        try text.write(to: post, atomically: true, encoding: .utf8)
        html = try SiteRenderer(site: Site.load(from: root)).render(path: "/posts/hello-world/") ?? ""
        #expect(html.contains(#"<style id="cardstock-lightbox">"#))
        #expect(html.contains(#"<script id="cardstock-lightbox-script">"#))
        let script = try #require(html.range(of: "cardstock-lightbox-script"))
        let bodyEnd = try #require(html.range(of: "</body>"))
        #expect(script.lowerBound < bodyEnd.lowerBound)
    }

    @Test func defaultDescriptions() {
        #expect(ImageImporter.defaultAlt(for: URL(filePath: "/x/beach_day-2.jpg")) == "Beach day 2")
        #expect(ImageImporter.cleanAlt(" a [b]\nc ") == "a b c")
    }
}
