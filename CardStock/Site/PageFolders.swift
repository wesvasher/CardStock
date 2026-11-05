import Foundation

/// Folders in the Pages list. They only organize the list: a page's folder
/// is its `folder:` front matter (`Recipes/Soups`), and folders with no
/// pages yet are kept in site.json's `pageFolders`. Page files stay in
/// `pages/` and their addresses never change. Paths use `/` between
/// names; the top of the list is the empty path.
enum PageFolders {
    static let top = ""

    /// A folder name from what someone typed: trimmed, with no `/`. Nil
    /// when nothing is left. Names keep their capitals and spaces, since
    /// they're never part of an address.
    static func name(for typed: String) -> String? {
        let name = typed.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    static func join(_ parent: String, _ name: String) -> String {
        parent.isEmpty ? name : parent + "/" + name
    }

    /// `Recipes/Soups` → `Recipes`; `Recipes` → the top.
    static func parent(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return top }
        return String(path[..<slash])
    }

    /// `Recipes/Soups` → `Soups`.
    static func name(of path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    /// Whether `path` is `folder` or inside it. Everything is inside the top.
    static func isInside(_ path: String, _ folder: String) -> Bool {
        folder.isEmpty || path == folder || path.hasPrefix(folder + "/")
    }

    /// `path` and the folders holding it: `A/B/C` → `A`, `A/B`, `A/B/C`.
    static func ancestors(of path: String) -> [String] {
        var result: [String] = []
        var current = path
        while !current.isEmpty {
            result.insert(current, at: 0)
            current = parent(of: current)
        }
        return result
    }

    /// Cleans up a stored path: no empty parts or stray spaces.
    static func normalized(_ path: String) -> String {
        path.split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "/")
    }

    /// Every folder: the saved ones, the ones pages are in, and the folders
    /// holding them, in name order (`A`, `A/B`, `B`).
    static func all(saved: [String], pages: [String]) -> [String] {
        let paths = Set((saved + pages).map(normalized).filter { !$0.isEmpty }.flatMap(ancestors(of:)))
        return paths.sorted { a, b in
            let x = a.split(separator: "/"), y = b.split(separator: "/")
            for (p, q) in zip(x, y) where p != q {
                return p.localizedStandardCompare(q) == .orderedAscending
            }
            return x.count < y.count
        }
    }

    /// The folders directly inside `parent`.
    static func children(of parent: String, in all: [String]) -> [String] {
        all.filter { self.parent(of: $0) == parent }
    }

    /// Where `path` goes when the folder `from` becomes `to` (the top when
    /// `to` is empty, so `from`'s contents move up a level when it's
    /// removed). Paths outside `from` stay as they are.
    static func moved(_ path: String, from: String, to: String) -> String {
        guard !from.isEmpty, isInside(path, from) else { return path }
        let rest = path.dropFirst(from.count).drop { $0 == "/" }
        return rest.isEmpty ? to : join(to, String(rest))
    }

    /// What's wrong with moving or renaming the folder `from` to `to`, or nil.
    static func moveProblem(from: String, to: String, in all: [String]) -> String? {
        if to == from { return nil }
        if isInside(to, from) { return "A folder can't go inside itself." }
        if all.contains(to) { return "There's already a folder named “\(name(of: to))” there." }
        return nil
    }
}
