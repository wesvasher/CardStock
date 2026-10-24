import Foundation

/// A page layout: an HTML file in `theme/layouts/` that arranges a page's
/// text, chosen per page with `layout:` in the front matter. Pages without
/// one use their type's own template ("Standard").
///
/// A comment at the top of the file describes it:
///
///     <!--
///     name: Hero
///     description: A big cover image with the title over it.
///     areas: Intro, Text
///     main: Text
///     types: page, post, product
///     -->
///
/// `areas` are the places for the page's own text, filled in order by the
/// sections between section breaks. Without breaks, all the text goes into
/// the `main` area (the first area when not given). `types` lists the page
/// types it suits (`type:` values such as `page` or `post`, or `item`,
/// `category` and `collection` for those pages of every collection);
/// without it, every type.
struct PageLayout: Identifiable, Equatable, Sendable {
    /// The file name without `.html`; what `layout:` holds.
    let id: String
    var name: String
    var description: String
    var areas: [String]
    var mainArea: String
    /// The `types` words, lowercased.
    var types: [String]
    /// The template, without the description comment.
    var source: String

    static let folder = "theme/layouts"
    /// The line that splits a page's Markdown into sections.
    static let sectionBreak = "<!-- section -->"

    /// An SF Symbol for menus and cards: the starter layouts have their own,
    /// others get one from how many areas they have.
    var systemImage: String {
        switch id {
        case "hero": "rectangle.topthird.inset.filled"
        case "landing": "rectangle.stack"
        case "sidebar": "sidebar.right"
        case "two-columns": "rectangle.split.2x1"
        case "wide": "arrow.left.and.right.square"
        default:
            switch areas.count {
            case ...1: "rectangle"
            case 2: "rectangle.split.2x1"
            default: "rectangle.split.3x1"
            }
        }
    }

    /// The icon for Standard (no layout).
    static let standardImage = "doc.text"

    func suits(_ kind: ContentKind) -> Bool {
        types.isEmpty || types.contains { Self.word($0, matches: kind) }
    }

    /// True when a `types` word covers a kind of page.
    static func word(_ word: String, matches kind: ContentKind) -> Bool {
        switch word {
        case "item", "items": kind.isItem
        case "category", "categories": kind.isCategory
        case "collection", "main": kind.isMain
        default: ContentKind(rawValue: word) == kind
        }
    }

    init(id: String, source: String) {
        self.id = id
        var name = id.replacingOccurrences(of: "-", with: " ").capitalized
        var description = ""
        var areas: [String] = []
        var main = ""
        var types: [String] = []
        var body = source
        let trimmed = source.drop { $0.isWhitespace }
        if trimmed.hasPrefix("<!--"), let end = trimmed.range(of: "-->") {
            let header = trimmed[trimmed.index(trimmed.startIndex, offsetBy: 4)..<end.lowerBound]
            for line in header.split(whereSeparator: \.isNewline) {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                let list = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                switch key {
                case "name": if !value.isEmpty { name = value }
                case "description": description = value
                case "areas": areas = list
                case "main": main = value
                case "types": types = list.map { $0.lowercased() }
                default: break
                }
            }
            body = String(trimmed[end.upperBound...].drop { $0.isNewline })
        }
        self.name = name
        self.description = description
        self.areas = areas
        self.mainArea = areas.contains(main) ? main : areas.first ?? ""
        self.types = types
        self.source = body
    }

    // MARK: - Sections

    /// Splits Markdown at section-break lines (not ones inside code blocks).
    static func sections(of markdown: String) -> [String] {
        var sections: [String] = []
        var current: [Substring] = []
        var fence: String?
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if let open = fence {
                if t.hasPrefix(open) { fence = nil }
            } else if t.hasPrefix("```") || t.hasPrefix("~~~") {
                fence = String(t.prefix(3))
            } else if isSectionBreak(t) {
                sections.append(current.joined(separator: "\n"))
                current = []
                continue
            }
            current.append(line)
        }
        sections.append(current.joined(separator: "\n"))
        return sections.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// `<!-- section -->`, ignoring case and spacing.
    static func isSectionBreak(_ line: String) -> Bool {
        let t = line.lowercased().replacingOccurrences(of: " ", with: "")
        return t == "<!--section-->"
    }

    /// Which text goes in each area: sections fill the areas in order, the
    /// last area takes any extra sections, and text without breaks goes in
    /// the main area. Keys are area numbers from 1.
    func areaText(_ sections: [String]) -> [Int: String] {
        guard !areas.isEmpty else { return [:] }
        if sections.count <= 1 {
            let main = (areas.firstIndex(of: mainArea) ?? 0) + 1
            return [main: sections.first ?? ""]
        }
        var result: [Int: String] = [:]
        for (i, text) in sections.enumerated() {
            let area = min(i, areas.count - 1) + 1
            result[area] = result[area].map { $0 + "\n\n" + text } ?? text
        }
        return result
    }

    // MARK: - Loading

    /// The site's layouts, or CardStock's built-in ones when the site has
    /// no layouts folder. Sorted by name.
    static func load(root: URL) -> [PageLayout] {
        let folder = root.appending(path: Self.folder)
        let dir = FileManager.default.fileExists(atPath: folder.path) ? folder : builtInFolder
        guard let dir, let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        return files
            .filter { $0.pathExtension.lowercased() == "html" }
            .compactMap { url in
                (try? String(contentsOf: url, encoding: .utf8)).map {
                    PageLayout(id: url.deletingPathExtension().lastPathComponent, source: $0)
                }
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static var builtInFolder: URL? {
        Bundle.main.url(forResource: "StarterSite", withExtension: nil)?.appending(path: Self.folder)
    }

    /// Copies the built-in layouts into sites made before layouts existed.
    /// Returns true if they were added.
    @discardableResult
    static func ensureLayouts(in root: URL) throws -> Bool {
        let target = root.appending(path: Self.folder)
        guard !FileManager.default.fileExists(atPath: target.path), let source = builtInFolder else { return false }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: target)
        return true
    }
}
