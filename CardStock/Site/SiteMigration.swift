import Foundation

/// Moves sites made before page types into the one-folder layout: every
/// page in `pages/`, with a `type:` line saying what it is.
enum SiteMigration {
    struct Result: Equatable, Sendable {
        var posts = 0
        var projects = 0
        var isEmpty: Bool { posts == 0 && projects == 0 }
    }

    /// Posts become blog posts (`type: post`). Projects become static
    /// pages; their old /portfolio/ addresses
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
                    redirects.append("/portfolio/\(slug)/ \(ContentKind.page.path(for: newSlug)) 301")
                } else {
                    result.posts += 1
                    if newSlug != slug { redirects.append("/posts/\(slug)/ \(ContentKind.post.path(for: newSlug)) 301") }
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

    // MARK: - Page addresses (0.6)

    /// Moves a site from the old addresses (static pages at `/<name>/`,
    /// posts at `/posts/<name>/`, other collection pages at `/<id>/<name>/`)
    /// to the current ones (`/pages/<name>/`, `/<id>/pages/<name>/`). Links
    /// to the old addresses in pages and in the top bar and footer are
    /// updated, and `static/_redirects` sends the old addresses to the new
    /// ones. Runs once: site.json's `addressVersion` records it. Returns how
    /// many pages moved.
    @discardableResult
    static func moveAddresses(in root: URL) throws -> Int {
        var site = try Site.load(from: root)
        guard site.config.addressVersion < SiteConfig.currentAddressVersion else { return 0 }
        let moves = addressMoves(for: site)

        for item in site.items {
            let body = rewriteLinks(in: item.body, moves)
            guard body != item.body else { continue }
            var updated = item
            updated.body = body
            try updated.fileText.write(to: item.fileURL, atomically: true, encoding: .utf8)
        }
        func fix(_ links: inout [SiteConfig.NavLink]) {
            for i in links.indices { links[i].url = newAddress(for: links[i].url, moves) ?? links[i].url }
        }
        fix(&site.config.nav)
        fix(&site.config.header.leftLinks)
        fix(&site.config.header.centerLinks)
        fix(&site.config.footer.links)
        site.config.addressVersion = SiteConfig.currentAddressVersion
        try site.saveConfig()
        try addRedirects(moves.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value) 301" }, in: root)
        return moves.count
    }

    /// Old address → new address, for every published page that moved.
    static func addressMoves(for site: Site) -> [String: String] {
        var moves: [String: String] = [:]
        for item in site.items where !item.isLinkMenu {
            let old = item.kind.legacyPath(for: item.slug)
            if old != item.path { moves[old] = item.path }
        }
        return moves
    }

    /// The new address for a link to a moved page, keeping any `?query` or
    /// `#part`; nil when it didn't move.
    static func newAddress(for link: String, _ moves: [String: String]) -> String? {
        guard link.hasPrefix("/"), !link.hasPrefix("//") else { return nil }
        let cut = link.firstIndex { $0 == "?" || $0 == "#" } ?? link.endIndex
        var path = String(link[..<cut])
        if path.hasSuffix("/index.html") { path = String(path.dropLast("index.html".count)) }
        if !path.hasSuffix("/") && !path.contains(".") { path += "/" }
        guard let new = moves[path] else { return nil }
        return new + link[cut...]
    }

    /// Updates Markdown links (`[text](/about/)`) and HTML ones
    /// (`href="/about/"`) to moved pages.
    static func rewriteLinks(in text: String, _ moves: [String: String]) -> String {
        guard !moves.isEmpty, text.contains("/") else { return text }
        var result = text
        for pattern in [#"\]\((/[^)\s]*)"#, #"href="(/[^"]*)""#] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = result as NSString
            var replaced = result
            for match in regex.matches(in: result, range: NSRange(location: 0, length: ns.length)).reversed() {
                let range = match.range(at: 1)
                guard let new = newAddress(for: ns.substring(with: range), moves),
                      let swiftRange = Range(range, in: replaced) else { continue }
                replaced.replaceSubrange(swiftRange, with: new)
            }
            result = replaced
        }
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
