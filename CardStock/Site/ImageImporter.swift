import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Copies images into a site's media folder and returns the Markdown that
/// shows them.
///
/// Optimized (the default): a full-size version scaled to at most
/// `largeMaxPixels` on its long side, plus a smaller inline version that
/// links to it (opened in the lightbox). Photo metadata such as GPS location
/// is not copied. Full resolution: the original file, converted only when
/// browsers can't show its format (e.g. HEIC).
enum ImageImporter {
    enum Mode: String, Sendable, CaseIterable {
        case optimized, original
    }

    struct Item: Sendable {
        var source: URL
        var alt: String
    }

    /// Long side of the full-size image people see in the lightbox.
    static let largeMaxPixels = 2400
    /// Long side of the image shown in the page (sharp on Retina at typical widths).
    static let inlineMaxPixels = 1200
    static let jpegQuality = 0.82

    /// Formats browsers show directly.
    private static let webFormats: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "avif", "svg"]
    /// Formats copied as-is even when optimizing (scaling would break them).
    private static let copyAsIs: Set<String> = ["gif", "svg"]
    static let supportedExtensions: Set<String> = webFormats.union(["heic", "heif", "tif", "tiff", "bmp"])

    static func isImage(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// The folder and public path where a content item's images live.
    static func location(for item: ContentItem, root: URL) -> (folder: URL, urlPrefix: String) {
        let relative = "media/\(item.kind.mediaFolder)/\(item.slug)"
        return (root.appending(path: relative), "/" + relative)
    }

    /// Imports each image and returns one Markdown snippet per image.
    static func importImages(_ items: [Item], folder: URL, urlPrefix: String, mode: Mode) throws -> [String] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try items.map { try importImage($0, folder: folder, urlPrefix: urlPrefix, mode: mode) }
    }

    private static func importImage(_ item: Item, folder: URL, urlPrefix: String, mode: Mode) throws -> String {
        let ext = item.source.pathExtension.lowercased()
        let alt = cleanAlt(item.alt)
        let base = uniqueBase(Site.slugify(item.source.deletingPathExtension().lastPathComponent), in: folder)

        // Copy files that are already web-ready (or can't be scaled) as they are.
        if copyAsIs.contains(ext) || (mode == .original && webFormats.contains(ext)) {
            let name = "\(base).\(ext == "jpeg" ? "jpg" : ext)"
            try FileManager.default.copyItem(at: item.source, to: folder.appending(path: name))
            return "![\(alt)](\(urlPrefix)/\(name))"
        }

        guard let source = CGImageSourceCreateWithURL(item.source as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let size = pixelSize(source)
        else {
            throw SiteError("“\(item.source.lastPathComponent)” couldn't be read as an image.")
        }
        let longSide = max(size.width, size.height)
        // Keep PNGs (screenshots, graphics) as PNG so text stays sharp.
        let type: UTType = ext == "png" ? .png : .jpeg
        let outExt = type == .png ? "png" : "jpg"

        if mode == .original || longSide <= inlineMaxPixels {
            let name = "\(base).\(outExt)"
            try write(source, maxPixels: longSide, type: type, to: folder.appending(path: name))
            return "![\(alt)](\(urlPrefix)/\(name))"
        }

        let large = "\(base).\(outExt)"
        let small = "\(base)-small.\(outExt)"
        try write(source, maxPixels: min(longSide, largeMaxPixels), type: type, to: folder.appending(path: large))
        try write(source, maxPixels: inlineMaxPixels, type: type, to: folder.appending(path: small))
        return "[![\(alt)](\(urlPrefix)/\(small))](\(urlPrefix)/\(large))"
    }

    /// Pixel size of an image file, or nil when it can't be read (e.g. SVG).
    static func pixelSize(of url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return pixelSize(source)
    }

    /// Pixel size with the photo's rotation applied.
    private static func pixelSize(_ source: CGImageSource) -> (width: Int, height: Int)? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? (h, w) : (w, h)
    }

    /// Scales (never enlarges), applies rotation, and writes without metadata.
    static func write(_ source: CGImageSource, maxPixels: Int, type: UTType, to url: URL) throws {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        else {
            throw SiteError("Couldn't convert the image “\(url.lastPathComponent)”.")
        }
        var properties: [CFString: Any] = [:]
        if type == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] = jpegQuality
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw SiteError("Couldn't save the image “\(url.lastPathComponent)”.")
        }
    }

    /// A file name base not used by any existing image in the folder.
    private static func uniqueBase(_ base: String, in folder: URL) -> String {
        let existing = Set(((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .map { ($0 as NSString).deletingPathExtension.lowercased() })
        var candidate = base
        var n = 2
        while existing.contains(candidate) || existing.contains("\(candidate)-small") {
            candidate = "\(base)-\(n)"
            n += 1
        }
        return candidate
    }

    /// Alt text that can't break the Markdown.
    static func cleanAlt(_ alt: String) -> String {
        alt.replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// A readable default description from a file name: "beach_day-2" → "Beach day 2".
    static func defaultAlt(for url: URL) -> String {
        let words = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ").joined(separator: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
