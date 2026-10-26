import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

extension SiteConfig {
    /// The site's icon (Configuration → Site Details → Site Icon): one square
    /// image that CardStock turns into the home screen icons for iPhone, iPad
    /// and Android, and the favicon. Saved as `icon` in site.json.
    struct Icon: Codable, Equatable, Sendable {
        /// Address of the image in media/, such as /media/files/icon.png.
        var image = ""
        /// Fills transparent parts on iPhone and iPad (which would turn
        /// them black) and around Android's shaped icon; also the manifest's
        /// background and theme color.
        var background = "#ffffff"
        /// The name under the icon on a home screen. Empty uses the title.
        var name = ""
        /// Off: the favicon is made from `image`. On: `favicon` is used as is.
        var customFavicon = false
        /// Address of the favicon file in media/ (any image: PNG, GIF, ICO, SVG).
        var favicon = ""

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Icon()
            image = try c.decodeIfPresent(String.self, forKey: .image) ?? d.image
            background = try c.decodeIfPresent(String.self, forKey: .background) ?? d.background
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? d.name
            customFavicon = try c.decodeIfPresent(Bool.self, forKey: .customFavicon) ?? d.customFavicon
            favicon = try c.decodeIfPresent(String.self, forKey: .favicon) ?? d.favicon
        }

        var hasImage: Bool { !image.trimmingCharacters(in: .whitespaces).isEmpty }

        /// The custom favicon's address, when it's on and chosen.
        var customFaviconPath: String? {
            let path = favicon.trimmingCharacters(in: .whitespaces)
            return customFavicon && !path.isEmpty ? path : nil
        }

        /// True when there's anything to publish.
        var isSet: Bool { hasImage || customFaviconPath != nil }

        func shownName(siteTitle: String) -> String {
            let n = name.trimmingCharacters(in: .whitespaces)
            return n.isEmpty ? siteTitle : n
        }

        /// `background` as `#rrggbb`, white when it isn't a color.
        var backgroundHex: String {
            SiteIcon.rgb(background) != nil ? background.lowercased() : "#ffffff"
        }
    }
}

/// Makes the files a site icon needs and the tags that point to them.
enum SiteIcon {
    struct Size: Sendable, Equatable {
        let file: String
        let pixels: Int
        /// Fill the background (no transparency).
        let opaque: Bool
        /// How much of the icon the image fills (Android's shaped icons
        /// keep their artwork in the middle 80%).
        let scale: Double
    }

    /// For iPhone and iPad: square and opaque; iOS rounds the corners.
    static let appleTouch = Size(file: "apple-touch-icon.png", pixels: 180, opaque: true, scale: 1)
    /// Android's regular icons, for launchers that show them as they are.
    static let android192 = Size(file: "icon-192.png", pixels: 192, opaque: false, scale: 1)
    static let android512 = Size(file: "icon-512.png", pixels: 512, opaque: false, scale: 1)
    /// Android's "maskable" icon, cropped to the phone's own shape.
    static let maskable = Size(file: "icon-maskable-512.png", pixels: 512, opaque: true, scale: 0.8)
    /// The browser tab icon, unless a custom favicon is used.
    static let favicon = Size(file: "favicon-32.png", pixels: 32, opaque: false, scale: 1)

    static let manifestFile = "site.webmanifest"

    /// The image files to make for these settings.
    static func sizes(for icon: SiteConfig.Icon) -> [Size] {
        guard icon.hasImage else { return [] }
        var sizes = [appleTouch, android192, android512, maskable]
        if icon.customFaviconPath == nil { sizes.append(favicon) }
        return sizes
    }

    // MARK: - Head and manifest

    /// The `<link>` and `<meta>` tags for every page's `<head>`, or nil
    /// when there's no icon.
    static func headHTML(_ config: SiteConfig) -> String? {
        let icon = config.icon
        guard icon.isSet else { return nil }
        var tags: [String] = []
        if let path = icon.customFaviconPath {
            let type = mimeType(forPath: path).map { " type=\"\($0)\"" } ?? ""
            tags.append("<link rel=\"icon\" href=\"\(escapeHTML(path))\"\(type)>")
        } else {
            tags.append("<link rel=\"icon\" href=\"/\(favicon.file)\" sizes=\"32x32\" type=\"image/png\">")
        }
        if icon.hasImage {
            let name = escapeHTML(icon.shownName(siteTitle: config.title))
            tags.append("<link rel=\"apple-touch-icon\" href=\"/\(appleTouch.file)\">")
            tags.append("<meta name=\"apple-mobile-web-app-title\" content=\"\(name)\">")
            tags.append("<link rel=\"manifest\" href=\"/\(manifestFile)\">")
        }
        return tags.map { "  " + $0 + "\n" }.joined()
    }

    /// The web app manifest Android reads for the name and icons.
    static func manifest(_ config: SiteConfig) -> String {
        let icon = config.icon
        let name = icon.shownName(siteTitle: config.title)
        let fullName = config.title.trimmingCharacters(in: .whitespaces).isEmpty ? name : config.title
        func entry(_ size: Size, purpose: String) -> [String: String] {
            ["src": "/" + size.file, "sizes": "\(size.pixels)x\(size.pixels)", "type": "image/png", "purpose": purpose]
        }
        let object: [String: Any] = [
            "name": fullName,
            "short_name": name,
            "start_url": "/",
            "display": "browser",
            "background_color": icon.backgroundHex,
            "theme_color": icon.backgroundHex,
            "icons": [entry(android192, purpose: "any"), entry(android512, purpose: "any"),
                      entry(maskable, purpose: "maskable")],
        ]
        let data = (try? JSONSerialization.data(withJSONObject: object,
                                                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    static func mimeType(forPath path: String) -> String? {
        let ext = (path as NSString).pathExtension.lowercased()
        if ext == "ico" { return "image/x-icon" }
        return UTType(filenameExtension: ext)?.preferredMIMEType
    }

    // MARK: - Images

    /// The icon image file in the site folder, from its address.
    static func sourceURL(_ path: String, root: URL) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains("://") else { return nil }
        let url = root.appending(path: String(trimmed.drop { $0 == "/" })).standardizedFileURL
        guard url.path.hasPrefix(root.standardizedFileURL.path + "/") else { return nil }
        return url
    }

    /// Reads an image file (PNG, JPEG, HEIC, GIF, …; not SVG) at up to
    /// 1024 pixels on its long side, upright.
    static func loadImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Draws one icon: the image fitted into the square (scaled to `scale`
    /// of it, centered), over the background when `opaque`.
    static func render(_ image: CGImage, size: Size, background: String) -> CGImage? {
        let px = size.pixels
        guard let context = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        let side = Double(px)
        if size.opaque {
            let (r, g, b) = rgb(background) ?? (1, 1, 1)
            context.setFillColor(red: r, green: g, blue: b, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
        let w = Double(max(image.width, 1)), h = Double(max(image.height, 1))
        let box = side * size.scale
        let fit = min(box / w, box / h)
        context.draw(image, in: CGRect(x: (side - w * fit) / 2, y: (side - h * fit) / 2, width: w * fit, height: h * fit))
        return context.makeImage()
    }

    static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// Writes the icon images and the manifest into a built site. Returns
    /// warnings for files that are missing or can't be read.
    static func write(_ config: SiteConfig, root: URL, to output: URL) throws -> [String] {
        let icon = config.icon
        var warnings: [String] = []
        if let path = icon.customFaviconPath,
           sourceURL(path, root: root).map({ FileManager.default.fileExists(atPath: $0.path) }) != true {
            warnings.append("The favicon \(path) isn't in your site's Files.")
        }
        guard icon.hasImage else { return warnings }
        guard let url = sourceURL(icon.image, root: root), let image = loadImage(url) else {
            warnings.append("The site icon \(icon.image) is missing or isn't a PNG or JPEG image, so no home screen icon was published.")
            return warnings
        }
        for size in sizes(for: icon) {
            guard let cg = render(image, size: size, background: icon.background), let png = pngData(cg) else {
                throw SiteError("Couldn't make the site icon \(size.file).")
            }
            try png.write(to: output.appending(path: size.file))
        }
        try Data(manifest(config).utf8).write(to: output.appending(path: manifestFile))
        if let pixels = ImageImporter.pixelSize(of: url), min(pixels.width, pixels.height) < 512 {
            warnings.append("The site icon is \(pixels.width) × \(pixels.height) pixels. Use one at least 512 × 512 (1024 × 1024 is best) so it's sharp on phones.")
        }
        return warnings
    }

    /// Parses `#rgb` or `#rrggbb` into 0–1 components.
    static func rgb(_ hex: String) -> (Double, Double, Double)? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        guard s.hasPrefix("#") else { return nil }
        s.removeFirst()
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return (Double((v >> 16) & 0xff) / 255, Double((v >> 8) & 0xff) / 255, Double(v & 0xff) / 255)
    }
}
