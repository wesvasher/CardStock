import Foundation

/// Moves sites made before page types into the one-folder layout: every
/// page in `pages/`, with a `type:` line saying what it is.
enum SiteMigration {
    struct Result: Equatable, Sendable {
        var posts = 0
        var projects = 0
        var isEmpty: Bool { posts == 0 && projects == 0 }
    }

    /// Posts keep their /posts/<name>/ address (`type: post`). Projects
    /// become static pages at /<name>/; their old /portfolio/ addresses
    /// redirect there (static/_redirects, read by Cloudflare Pages), and a
    /// menu link titled Portfolio is removed. Images aren't moved.
    @discardableResult
    static func run(in root: URL) throws -> Result {
        let fm = FileManager.default
        let pages = root.appending(path: ContentKind.folder)
        var result = Result()
        var redirects: [String] = []

        for (folder, type) in [("posts", "post"), ("projects", nil as String?)] {
            let source = root.appending(path: folder)
            let files = ((try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil,
                                                       options: [.skipsHiddenFiles])) ?? [])
                .filter { $0.pathExtension.lowercased() == "md" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            guard !files.isEmpty else { continue }
            try fm.createDirectory(at: pages, withIntermediateDirectories: true)

            for file in files {
                let slug = file.deletingPathExtension().lastPathComponent
                var newSlug = slug
                var n = 2
                while fm.fileExists(atPath: pages.appending(path: "\(newSlug).md").path)
                        || (type == nil && Site.unavailablePageSlugs.contains(newSlug)) {
                    newSlug = "\(slug)-\(n)"
                    n += 1
                }
                var text = try String(contentsOf: file, encoding: .utf8)
                if let type { text = setType(type, in: text) }
                try text.write(to: pages.appending(path: "\(newSlug).md"), atomically: true, encoding: .utf8)
                try fm.removeItem(at: file)
                if type == nil {
                    result.projects += 1
                    redirects.append("/portfolio/\(slug)/ /\(newSlug)/ 301")
                } else {
                    result.posts += 1
                    if newSlug != slug { redirects.append("/posts/\(slug)/ /posts/\(newSlug)/ 301") }
                }
            }
            // Leave the folder only if something else is still in it.
            if ((try? fm.contentsOfDirectory(atPath: source.path)) ?? []).filter({ $0 != ".DS_Store" }).isEmpty {
                try? fm.removeItem(at: source)
            }
        }

        if result.projects > 0 {
            redirects.append("/portfolio/ / 301")
            try removePortfolioMenuLink(in: root)
        }
        if !redirects.isEmpty { try addRedirects(redirects, in: root) }
        return result
    }

    /// Adds `type: <type>` to a file's front matter (or gives it some).
    static func setType(_ type: String, in text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        if normalized.hasPrefix("---\n") {
            return "---\ntype: \(type)\n" + normalized.dropFirst(4)
        }
        return "---\ntype: \(type)\n---\n\n" + normalized
    }

    private static func addRedirects(_ lines: [String], in root: URL) throws {
        let url = root.appending(path: "static/_redirects")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let existing = Set(text.split(separator: "\n").map(String.init))
        let new = lines.filter { !existing.contains($0) }
        guard !new.isEmpty else { return }
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        text += new.joined(separator: "\n") + "\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func removePortfolioMenuLink(in root: URL) throws {
        let url = root.appending(path: Site.configFile)
        guard let data = try? Data(contentsOf: url),
              var config = try? JSONDecoder().decode(SiteConfig.self, from: data)
        else { return }
        let before = config.nav.count
        // Only the starter site's own Portfolio link; a link someone renamed
        // stays (the redirect still takes it somewhere).
        config.nav.removeAll {
            ($0.url == "/portfolio/" || $0.url == "/portfolio")
                && $0.title.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("Portfolio") == .orderedSame
        }
        guard config.nav.count != before else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(config).write(to: url, options: .atomic)
    }
}
