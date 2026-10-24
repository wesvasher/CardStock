import Foundation

/// A box placed in a page's Markdown with a line of its own, such as
/// `<!-- newsletter -->`. Before the Markdown is formatted, those lines
/// (but not ones in code blocks) become placeholders, which the renderer
/// swaps for the box's HTML.
enum PageWidget: String, CaseIterable, Sendable {
    /// The mailing list sign-up box (Configuration → Mailing List).
    case newsletter
    /// A search field that opens the search page (Configuration → Search).
    case search

    /// The line typed (or inserted) in a page.
    var marker: String { "<!-- \(rawValue) -->" }
    /// What `markPlaces` turns the line into, for the renderer to find.
    var placeholder: String { "<!--cardstock:\(rawValue)-->" }

    /// True for this widget's line, ignoring case and spacing.
    func isMarker(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: " ", with: "") == "<!--\(rawValue)-->"
    }

    /// True when a page's Markdown has this widget's line outside code blocks.
    func isUsed(in markdown: String) -> Bool {
        var found = false
        Self.eachLine(of: markdown) { line in
            if isMarker(line) { found = true }
            return nil
        }
        return found
    }

    /// Turns every widget line outside code blocks into its placeholder.
    static func markPlaces(in markdown: String) -> String {
        guard markdown.contains("<!--") else { return markdown }
        return eachLine(of: markdown) { line in
            allCases.first { $0.isMarker(line) }?.placeholder
        }
    }

    /// Calls `replace` for each line outside fenced code blocks; a non-nil
    /// result replaces the line. Returns the text with the replacements.
    @discardableResult
    private static func eachLine(of markdown: String, _ replace: (String) -> String?) -> String {
        var fence: String?
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let t = line.trimmingCharacters(in: .whitespaces)
            if let open = fence {
                if t.hasPrefix(open) { fence = nil }
            } else if t.hasPrefix("```") || t.hasPrefix("~~~") {
                fence = String(t.prefix(3))
            } else if let replacement = replace(t) {
                return replacement
            }
            return String(line)
        }
        return lines.joined(separator: "\n")
    }
}
