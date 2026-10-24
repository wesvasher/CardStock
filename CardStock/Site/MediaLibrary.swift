import Foundation

/// A file in the site's `media/` folder, as listed on the Files page. An
/// optimized image's inline version (`name-small.jpg`) is shown with its
/// full-size file as one entry.
struct MediaFile: Identifiable, Hashable, Sendable {
    /// Relative to the site folder, e.g. `media/posts/trip/beach.jpg`.
    var path: String
    /// The inline `-small` version, when there is one.
    var smallPath: String?
    var size: Int64
    /// When the file was added to the folder.
    var added: Date
    /// Titles of the pages, posts and projects that use it.
    var usedIn: [String]
    /// Its tags (media.json).
    var tags: [String] = []

    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
    var folder: String { (path as NSString).deletingLastPathComponent }
    var isImage: Bool { ImageImporter.isImage(URL(filePath: path)) }
    var allPaths: [String] { [path] + (smallPath.map { [$0] } ?? []) }
}

/// Lists, adds and removes the files in a site's `media/` folder.
enum MediaLibrary {
    static let folderName = "media"
    /// Where files added on the Files page go.
    static let uploadsFolder = "media/files"

    // MARK: Listing

    /// Every file in media/, newest first.
    static func scan(_ site: Site) -> [MediaFile] {
        let root = site.root
        let fm = FileManager.default
        let media = root.appending(path: folderName)
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .creationDateKey, .addedToDirectoryDateKey]
        guard let walker = fm.enumerator(at: media, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        else { return [] }

        let base = root.standardizedFileURL.path + "/"
        var found: [String: (size: Int64, added: Date)] = [:]
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            let full = url.standardizedFileURL.path
            guard full.hasPrefix(base) else { continue }
            let added = values.addedToDirectoryDate ?? values.creationDate ?? .distantPast
            found[String(full.dropFirst(base.count))] = (Int64(values.fileSize ?? 0), added)
        }

        let usage = usage(in: site)
        var files: [MediaFile] = []
        for (path, info) in found {
            // "-small" files are listed with their full-size file.
            if let large = largePath(forSmall: path), found[large] != nil { continue }
            var file = MediaFile(path: path, smallPath: nil, size: info.size, added: info.added, usedIn: [])
            let small = smallPath(for: path)
            if let small, let smallInfo = found[small] {
                file.smallPath = small
                file.size += smallInfo.size
            }
            file.usedIn = file.allPaths.flatMap { usage[$0] ?? [] }.uniqued()
            file.tags = site.mediaTags[path]
            files.append(file)
        }
        return files.sorted { $0.added != $1.added ? $0.added > $1.added : $0.path < $1.path }
    }

    /// `media/a/b.jpg` → `media/a/b-small.jpg`.
    static func smallPath(for path: String) -> String? {
        let ns = path as NSString
        let ext = ns.pathExtension
        let base = ns.deletingPathExtension
        guard !base.hasSuffix("-small") else { return nil }
        return ext.isEmpty ? base + "-small" : "\(base)-small.\(ext)"
    }

    /// `media/a/b-small.jpg` → `media/a/b.jpg`.
    static func largePath(forSmall path: String) -> String? {
        let ns = path as NSString
        let base = ns.deletingPathExtension
        guard base.hasSuffix("-small") else { return nil }
        let large = String(base.dropLast(6))
        return ns.pathExtension.isEmpty ? large : "\(large).\(ns.pathExtension)"
    }

    // MARK: Where files are used

    /// Each media path the site refers to, with the titles of the items
    /// using it. Files used only by site.json, the theme or static files are
    /// listed as "Site settings" or "Theme".
    static func usage(in site: Site) -> [String: [String]] {
        var used: [String: [String]] = [:]
        func add(_ text: String, _ title: String) {
            for path in referencedPaths(in: text) where used[path]?.contains(title) != true {
                used[path, default: []].append(title)
            }
        }
        for item in site.items { add(item.fileText, item.title) }
        if let config = try? String(contentsOf: site.root.appending(path: Site.configFile), encoding: .utf8) {
            add(config, "Configuration")
        }
        for folder in ["theme", "static"] {
            let dir = site.root.appending(path: folder)
            guard let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker
            where ["html", "htm", "css", "js", "json", "xml", "txt", "md"].contains(url.pathExtension.lowercased()) {
                if let text = try? String(contentsOf: url, encoding: .utf8) { add(text, "Theme") }
            }
        }
        return used
    }

    /// Site-relative paths of media files a text refers to, such as
    /// `media/posts/trip/a.jpg` for `![](/media/posts/trip/a.jpg)`.
    static func referencedPaths(in text: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: #"/?media/[^\s)"'<>\]]+"#) else { return [] }
        let ns = text as NSString
        var paths: Set<String> = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            var path = ns.substring(with: match.range)
            if path.hasPrefix("/") { path.removeFirst() }
            if let cut = path.firstIndex(where: { $0 == "?" || $0 == "#" }) { path = String(path[..<cut]) }
            path = path.removingPercentEncoding ?? path
            guard !path.contains(".."), !(path as NSString).pathExtension.isEmpty else { continue }
            paths.insert(path)
        }
        return paths
    }

    // MARK: Markdown

    /// Markdown that shows the file in a page: an image (linked to its
    /// full-size version when it has an inline one), or a link for other files.
    static func markdown(for file: MediaFile) -> String {
        let url = { (path: String) in "/" + (path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path) }
        let description = ImageImporter.cleanAlt(ImageImporter.defaultAlt(for: URL(filePath: file.path)))
        guard file.isImage else { return "[\(description)](\(url(file.path)))" }
        if let small = file.smallPath {
            return "[![\(description)](\(url(small)))](\(url(file.path)))"
        }
        return "![\(description)](\(url(file.path)))"
    }

    // MARK: Adding and removing

    /// Copies files into media/files/ with web-safe names, never
    /// overwriting. Returns the new paths.
    @discardableResult
    static func addFiles(_ urls: [URL], to root: URL) throws -> [String] {
        let fm = FileManager.default
        let folder = root.appending(path: uploadsFolder)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var added: [String] = []
        for source in urls {
            let ext = source.pathExtension.lowercased()
            var base = Site.slugify(source.deletingPathExtension().lastPathComponent)
            if base.isEmpty { base = "file" }
            func name(_ b: String) -> String { ext.isEmpty ? b : "\(b).\(ext)" }
            var candidate = base
            var n = 2
            while fm.fileExists(atPath: folder.appending(path: name(candidate)).path) {
                candidate = "\(base)-\(n)"
                n += 1
            }
            try fm.copyItem(at: source, to: folder.appending(path: name(candidate)))
            added.append("\(uploadsFolder)/\(name(candidate))")
        }
        return added
    }

    /// Copies a file (and its inline version) next to it as "name-copy",
    /// "name-copy-2" and so on. Returns the new file's path.
    @discardableResult
    static func duplicate(_ file: MediaFile, root: URL) throws -> String {
        let fm = FileManager.default
        let ns = file.path as NSString
        let folder = ns.deletingLastPathComponent
        let ext = ns.pathExtension
        let base = (ns.lastPathComponent as NSString).deletingPathExtension
        func path(_ b: String) -> String {
            let name = ext.isEmpty ? b : "\(b).\(ext)"
            return folder.isEmpty ? name : "\(folder)/\(name)"
        }
        var candidate = "\(base)-copy"
        var n = 2
        while fm.fileExists(atPath: root.appending(path: path(candidate)).path)
                || fm.fileExists(atPath: root.appending(path: path(candidate + "-small")).path) {
            candidate = "\(base)-copy-\(n)"
            n += 1
        }
        try fm.copyItem(at: root.appending(path: file.path), to: root.appending(path: path(candidate)))
        if let small = file.smallPath {
            try fm.copyItem(at: root.appending(path: small), to: root.appending(path: path(candidate + "-small")))
        }
        return path(candidate)
    }

    /// Moves a file (and its inline version) to the Mac's Trash.
    static func moveToTrash(_ file: MediaFile, root: URL) throws {
        for path in file.allPaths {
            let url = root.appending(path: path)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            }
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
