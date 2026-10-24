import Foundation

/// Writes the finished website into `public/`.
enum SiteBuilder {
    struct Report: Sendable {
        var pageCount: Int
        var warnings: [String]
    }

    static func build(_ site: Site) throws -> Report {
        let fm = FileManager.default
        let renderer = try SiteRenderer(site: site)
        let output = site.root.appending(path: "public")
        var warnings: [String] = []

        for item in site.items where item.kind == .page && Site.reservedSlugs.contains(item.slug) {
            warnings.append("pages/\(item.slug).md uses a reserved name and is hidden by /\(item.slug)/.")
        }
        for item in site.items where item.title == item.slug && item.frontMatter["title"] == nil {
            warnings.append("\(item.kind.folder)/\(item.slug).md has no title.")
        }

        // Build into a temporary folder, then swap it in, so a failed build
        // never leaves a half-written site.
        let staging = site.root.appending(path: ".public-building")
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)

        do {
            var count = 0
            for path in renderer.paths {
                guard let html = renderer.render(path: path) else { continue }
                let file = path.hasSuffix("/") ? path + "index.html" : path
                let url = staging.appending(path: String(file.dropFirst()))
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(html.utf8).write(to: url)
                count += 1
            }

            try copyContents(of: site.root.appending(path: "static"), to: staging)
            try copyFolder(site.root.appending(path: "theme/assets"), to: staging.appending(path: "assets"))
            try copyFolder(site.root.appending(path: "media"), to: staging.appending(path: "media"))

            if fm.fileExists(atPath: output.path) {
                try fm.removeItem(at: output)
            }
            try fm.moveItem(at: staging, to: output)
            return Report(pageCount: count, warnings: warnings)
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }

    private static func copyFolder(_ source: URL, to destination: URL) throws {
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try copyContents(of: source, to: destination)
    }

    /// Copies a folder's visible files into another, recursively.
    private static func copyContents(of source: URL, to destination: URL) throws {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(
            at: source, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        else { return }
        for child in children {
            let name = child.lastPathComponent
            // Keep Cloudflare's _headers/_redirects; skip exFAT/macOS metadata.
            if name.hasPrefix("._") || name == ".DS_Store" { continue }
            let target = destination.appending(path: name)
            if (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
                try copyContents(of: child, to: target)
            } else {
                if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                try fm.copyItem(at: child, to: target)
            }
        }
    }
}
