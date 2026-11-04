import Foundation

/// Folders inside `media/`: listing, making, renaming, moving and trashing
/// them, and moving files between them. Every move returns the old path →
/// new path of each file that moved (`media/a.jpg` → `media/photos/a.jpg`),
/// which `rewriteReferences` uses to keep links in pages working.
extension MediaLibrary {
    /// An empty file that keeps an empty folder in git (which only stores files).
    static let keepFile = ".gitkeep"

    /// Every folder under media/, as site-relative paths (`media/photos`,
    /// `media/photos/2026`), each followed by its subfolders, by name.
    /// media/ itself isn't listed.
    static func folders(in root: URL) -> [String] {
        let media = root.appending(path: folderName)
        guard let walker = FileManager.default.enumerator(
            at: media, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        let base = root.standardizedFileURL.path + "/"
        var found: [String] = []
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let full = url.standardizedFileURL.path
            guard full.hasPrefix(base) else { continue }
            found.append(String(full.dropFirst(base.count)))
        }
        return found.sorted(by: treeOrder)
    }

    /// Compares paths a part at a time, so a folder's subfolders come right
    /// after it (`photos`, `photos/2026`, `photos-2`).
    static func treeOrder(_ a: String, _ b: String) -> Bool {
        let x = a.split(separator: "/"), y = b.split(separator: "/")
        for (p, q) in zip(x, y) where p != q {
            return String(p).localizedStandardCompare(String(q)) == .orderedAscending
        }
        return x.count < y.count
    }

    /// The folder a path is in: `media/photos/a.jpg` → `media/photos`.
    static func parent(of path: String) -> String { (path as NSString).deletingLastPathComponent }

    /// A folder's own name: `media/photos/2026` → `2026`.
    static func name(of folder: String) -> String { (folder as NSString).lastPathComponent }

    /// Whether `path` is `folder` or inside it.
    static func isInside(_ path: String, _ folder: String) -> Bool {
        path == folder || path.hasPrefix(folder + "/")
    }

    /// A web-safe folder name for what someone typed ("Product Photos" →
    /// `product-photos`), or nil when nothing usable is left.
    static func folderName(for typed: String) -> String? {
        guard typed.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        let name = Site.slugify(typed)
        return name.isEmpty ? nil : name
    }

    // MARK: Making

    /// Makes a folder named after `typed` inside `parent` (a folder path,
    /// `media` for the top), adding -2, -3… if the name is taken. Returns
    /// its path.
    @discardableResult
    static func makeFolder(_ typed: String, in parent: String, root: URL) throws -> String {
        guard isInside(parent, folderName) else { throw SiteError("Folders go inside the media folder.") }
        guard let name = folderName(for: typed) else { throw SiteError("Type a name with letters or numbers.") }
        let path = unusedPath("\(parent)/\(name)", root: root)
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data().write(to: url.appending(path: keepFile))
        return path
    }

    // MARK: Moving files

    /// Moves files (each with its inline `-small` version) into `folder`.
    /// A name that's taken there gets -2, -3… Files already in the folder
    /// stay. Returns old → new for every path that moved.
    static func move(_ files: [MediaFile], to folder: String, root: URL) throws -> [String: String] {
        guard isInside(folder, folderName) else { throw SiteError("Files go inside the media folder.") }
        let fm = FileManager.default
        try fm.createDirectory(at: root.appending(path: folder), withIntermediateDirectories: true)
        var moves: [String: String] = [:]
        for file in files where parent(of: file.path) != folder {
            let target = unusedFilePath(in: folder, named: (file.path as NSString).lastPathComponent,
                                        withSmall: file.smallPath != nil, root: root)
            try fm.moveItem(at: root.appending(path: file.path), to: root.appending(path: target))
            moves[file.path] = target
            if let small = file.smallPath, let newSmall = smallPath(for: target),
               fm.fileExists(atPath: root.appending(path: small).path) {
                try fm.moveItem(at: root.appending(path: small), to: root.appending(path: newSmall))
                moves[small] = newSmall
            }
        }
        return moves
    }

    // MARK: Folders

    /// Renames a folder (to a web-safe version of `typed`). Returns its new
    /// path and old → new for every file inside.
    static func renameFolder(_ folder: String, to typed: String, root: URL) throws -> (path: String, moves: [String: String]) {
        guard folder != folderName, isInside(folder, folderName) else { throw SiteError("The media folder itself can't be renamed.") }
        guard let name = folderName(for: typed) else { throw SiteError("Type a name with letters or numbers.") }
        let target = "\(parent(of: folder))/\(name)"
        guard target != folder else { return (folder, [:]) }
        // Changing only capitals is the same folder on Mac drives; go via a temporary name.
        if target.lowercased() == folder.lowercased() {
            let temp = unusedPath(folder + "-renaming", root: root)
            let first = try relocate(folder, to: temp, root: root)
            let second = try relocate(temp, to: target, root: root)
            return (target, first.mapValues { second[$0] ?? $0 })
        }
        let path = unusedPath(target, root: root)
        return (path, try relocate(folder, to: path, root: root))
    }

    /// Moves a folder into another one (`media` for the top). Returns its
    /// new path and old → new for every file inside.
    static func moveFolder(_ folder: String, into destination: String, root: URL) throws -> (path: String, moves: [String: String]) {
        guard folder != folderName, isInside(folder, folderName), isInside(destination, folderName) else {
            throw SiteError("Folders go inside the media folder.")
        }
        guard !isInside(destination, folder) else { throw SiteError("A folder can't go inside itself.") }
        guard parent(of: folder) != destination else { return (folder, [:]) }
        let path = unusedPath("\(destination)/\(name(of: folder))", root: root)
        return (path, try relocate(folder, to: path, root: root))
    }

    /// Moves a folder and everything in it to the Mac's Trash.
    static func trashFolder(_ folder: String, root: URL) throws {
        guard folder != folderName, isInside(folder, folderName) else { throw SiteError("The media folder itself can't be deleted.") }
        try FileManager.default.trashItem(at: root.appending(path: folder), resultingItemURL: nil)
    }

    /// Every file path inside a folder, at any depth (hidden files left out).
    static func filePaths(in folder: String, root: URL) -> [String] {
        let base = root.standardizedFileURL.path + "/"
        guard let walker = FileManager.default.enumerator(
            at: root.appending(path: folder), includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        else { return [] }
        var paths: [String] = []
        for case let url as URL in walker where (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
            let full = url.standardizedFileURL.path
            if full.hasPrefix(base) { paths.append(String(full.dropFirst(base.count))) }
        }
        return paths
    }

    private static func relocate(_ folder: String, to target: String, root: URL) throws -> [String: String] {
        let inside = filePaths(in: folder, root: root)
        try FileManager.default.createDirectory(at: root.appending(path: parent(of: target)), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: root.appending(path: folder), to: root.appending(path: target))
        var moves: [String: String] = [:]
        for path in inside { moves[path] = target + path.dropFirst(folder.count) }
        return moves
    }

    /// `path`, or `path-2`, `path-3`… if something's there.
    private static func unusedPath(_ path: String, root: URL) -> String {
        let fm = FileManager.default
        var candidate = path
        var n = 2
        while fm.fileExists(atPath: root.appending(path: candidate).path) {
            candidate = "\(path)-\(n)"
            n += 1
        }
        return candidate
    }

    /// A free name for a file in `folder`: `name.jpg`, else `name-2.jpg`…,
    /// checking its `-small` version's name too.
    private static func unusedFilePath(in folder: String, named name: String, withSmall: Bool, root: URL) -> String {
        let fm = FileManager.default
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        func path(_ b: String) -> String { "\(folder)/" + (ext.isEmpty ? b : "\(b).\(ext)") }
        func taken(_ p: String) -> Bool {
            fm.fileExists(atPath: root.appending(path: p).path)
                || (withSmall && smallPath(for: p).map { fm.fileExists(atPath: root.appending(path: $0).path) } == true)
        }
        var candidate = base
        var n = 2
        while taken(path(candidate)) {
            candidate = "\(base)-\(n)"
            n += 1
        }
        return path(candidate)
    }

    // MARK: Keeping links working

    /// Updates links to moved files in a text (Markdown, HTML, JSON, CSS):
    /// `/media/a.jpg` becomes `/media/photos/a.jpg`, keeping a leading
    /// slash (or not), any `?query` or `#part`, and %-encoding when the
    /// original had it. Matches whole paths only.
    static func rewriteReferences(in text: String, _ moves: [String: String]) -> String {
        guard !moves.isEmpty, text.contains("media/"),
              let regex = try? NSRegularExpression(pattern: #"/?media/[^\s)"'<>\]]+"#) else { return text }
        let ns = text as NSString
        var result = text
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let found = ns.substring(with: match.range)
            let slash = found.hasPrefix("/") ? "/" : ""
            var path = slash.isEmpty ? found : String(found.dropFirst())
            var rest = ""
            if let cut = path.firstIndex(where: { $0 == "?" || $0 == "#" }) {
                rest = String(path[cut...])
                path = String(path[..<cut])
            }
            let decoded = path.removingPercentEncoding ?? path
            guard let new = moves[decoded], let range = Range(match.range, in: result) else { continue }
            let encoded = decoded != path
                ? (new.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? new) : new
            result.replaceSubrange(range, with: slash + encoded + rest)
        }
        return result
    }

    /// Rewrites links to moved files in the site's pages, site.json, theme
    /// and static files, and moves their tags in media.json. Pages must be
    /// saved first; reload the site after. Returns how many files changed.
    @discardableResult
    static func updateReferences(_ moves: [String: String], root: URL) throws -> Int {
        guard !moves.isEmpty else { return 0 }
        let fm = FileManager.default
        var changed = 0
        func fix(_ url: URL) throws {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
            let updated = rewriteReferences(in: text, moves)
            guard updated != text else { return }
            try updated.write(to: url, atomically: true, encoding: .utf8)
            changed += 1
        }
        try fix(root.appending(path: Site.configFile))
        for folder in [ContentKind.folder, "theme", "static"] {
            guard let walker = fm.enumerator(at: root.appending(path: folder), includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker
            where ["md", "markdown", "html", "htm", "css", "js", "json", "xml", "txt"].contains(url.pathExtension.lowercased()) {
                try fix(url)
            }
        }
        // Tags follow their files.
        var tags = MediaTags.load(from: root)
        var moved = false
        for (old, new) in moves {
            if let list = tags.tags.removeValue(forKey: old) {
                tags.tags[new] = list
                moved = true
            }
        }
        if moved { try tags.save(to: root) }
        return changed
    }
}
