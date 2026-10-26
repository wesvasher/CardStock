import Foundation

/// Text changes made by the formatting bar. Pure string logic (no UI), so
/// it can be tested: each function takes the text and selection and
/// returns the edit to make.
enum MarkdownFormatting {
    /// Replace `range` with `replacement`, then select `selection`.
    struct Edit: Equatable {
        var range: NSRange
        var replacement: String
        var selection: NSRange
    }

    enum LineStyle {
        case bullet, numbered, quote
    }

    // MARK: Inline: bold, italic, strikethrough, code

    /// Wraps the selection in `marker` (e.g. `**`), or removes it when the
    /// selection is already wrapped. With nothing selected, the word at the
    /// cursor is used, or empty markers are inserted around the cursor.
    static func toggleWrap(_ text: String, _ selection: NSRange, marker: String) -> Edit {
        let ns = text as NSString
        let m = (marker as NSString).length
        var sel = selection

        if sel.length == 0 {
            // Cursor between empty markers: remove them.
            if sel.location >= m, sel.location + m <= ns.length,
               ns.substring(with: NSRange(location: sel.location - m, length: m)) == marker,
               ns.substring(with: NSRange(location: sel.location, length: m)) == marker {
                return Edit(range: NSRange(location: sel.location - m, length: 2 * m), replacement: "",
                            selection: NSRange(location: sel.location - m, length: 0))
            }
            let word = wordRange(in: ns, at: sel.location)
            if word.length == 0 {
                return Edit(range: sel, replacement: marker + marker,
                            selection: NSRange(location: sel.location + m, length: 0))
            }
            sel = word
        }

        let selected = ns.substring(with: sel)
        let markerChar = (marker as NSString).character(at: 0)

        // Markers inside the selection: "**word**" selected.
        let lead = run(of: markerChar, in: ns, from: sel.location, forward: true, limit: sel.location + sel.length)
        let trail = run(of: markerChar, in: ns, from: sel.location + sel.length - 1, forward: false, limit: sel.location)
        if sel.length > 2 * m, isWrapped(lead, trail, m),
           selected.hasPrefix(marker), selected.hasSuffix(marker) {
            let inner = (selected as NSString).substring(with: NSRange(location: m, length: sel.length - 2 * m))
            return Edit(range: sel, replacement: inner,
                        selection: NSRange(location: sel.location, length: (inner as NSString).length))
        }

        // Markers just outside the selection: "**" + "word" + "**".
        let before = run(of: markerChar, in: ns, from: sel.location - 1, forward: false, limit: 0)
        let after = run(of: markerChar, in: ns, from: sel.location + sel.length, forward: true, limit: ns.length)
        if isWrapped(before, after, m) {
            let outer = NSRange(location: sel.location - m, length: sel.length + 2 * m)
            return Edit(range: outer, replacement: selected,
                        selection: NSRange(location: sel.location - m, length: sel.length))
        }

        return Edit(range: sel, replacement: marker + selected + marker,
                    selection: NSRange(location: sel.location + m, length: sel.length))
    }

    /// Whether runs of marker characters on both sides contain this marker.
    /// Single markers (`*`) need an odd run so `**bold**` isn't mistaken for
    /// italic; double markers (`**`) need at least two.
    private static func isWrapped(_ a: Int, _ b: Int, _ m: Int) -> Bool {
        m == 1 ? (a % 2 == 1 && b % 2 == 1) : (a >= m && b >= m)
    }

    /// Length of a run of `char` starting at `index` going one way.
    private static func run(of char: unichar, in ns: NSString, from index: Int, forward: Bool, limit: Int) -> Int {
        var i = index, count = 0
        while i >= 0 && i < ns.length && (forward ? i < limit : i >= limit) && ns.character(at: i) == char {
            count += 1
            i += forward ? 1 : -1
        }
        return count
    }

    /// The word around `location`, or an empty range when not in a word.
    static func wordRange(in ns: NSString, at location: Int) -> NSRange {
        func isWordChar(_ i: Int) -> Bool {
            guard i >= 0, i < ns.length, let scalar = Unicode.Scalar(ns.character(at: i)) else { return false }
            return CharacterSet.alphanumerics.contains(scalar) || scalar == "'" || scalar == "’"
        }
        var start = location, end = location
        while isWordChar(start - 1) { start -= 1 }
        while isWordChar(end) { end += 1 }
        return NSRange(location: start, length: end - start)
    }

    // MARK: HTML tags: fine print

    /// Wraps the selection in an HTML tag pair such as `<small>…</small>`,
    /// or removes it when the selection is already wrapped. With nothing
    /// selected, the word at the cursor is used, or an empty pair is
    /// inserted with the cursor inside.
    static func toggleTag(_ text: String, _ selection: NSRange, open: String, close: String) -> Edit {
        let ns = text as NSString
        let o = (open as NSString).length, c = (close as NSString).length
        var sel = selection

        func matches(_ s: String, at location: Int) -> Bool {
            let len = (s as NSString).length
            return location >= 0 && location + len <= ns.length
                && ns.substring(with: NSRange(location: location, length: len)) == s
        }

        if sel.length == 0 {
            if matches(open, at: sel.location - o) && matches(close, at: sel.location) {
                return Edit(range: NSRange(location: sel.location - o, length: o + c), replacement: "",
                            selection: NSRange(location: sel.location - o, length: 0))
            }
            let word = wordRange(in: ns, at: sel.location)
            if word.length == 0 {
                return Edit(range: sel, replacement: open + close,
                            selection: NSRange(location: sel.location + o, length: 0))
            }
            sel = word
        }

        let selected = ns.substring(with: sel)
        if sel.length >= o + c, selected.hasPrefix(open), selected.hasSuffix(close) {
            let inner = (selected as NSString).substring(with: NSRange(location: o, length: sel.length - o - c))
            return Edit(range: sel, replacement: inner,
                        selection: NSRange(location: sel.location, length: (inner as NSString).length))
        }
        if matches(open, at: sel.location - o) && matches(close, at: sel.location + sel.length) {
            return Edit(range: NSRange(location: sel.location - o, length: sel.length + o + c), replacement: selected,
                        selection: NSRange(location: sel.location - o, length: sel.length))
        }
        return Edit(range: sel, replacement: open + selected + close,
                    selection: NSRange(location: sel.location + o, length: sel.length))
    }

    // MARK: Links

    /// Makes the selection a link. A selected web address becomes the link's
    /// address; other text becomes the link's text with the address selected.
    static func link(_ text: String, _ selection: NSRange) -> Edit {
        let ns = text as NSString
        let selected = ns.substring(with: selection).trimmingCharacters(in: .whitespacesAndNewlines)
        if selected.isEmpty {
            let placeholder = "link text"
            return Edit(range: selection, replacement: "[\(placeholder)](https://)",
                        selection: NSRange(location: selection.location + 1, length: (placeholder as NSString).length))
        }
        if selected.hasPrefix("http://") || selected.hasPrefix("https://") || selected.hasPrefix("/") {
            return Edit(range: selection, replacement: "[](\(selected))",
                        selection: NSRange(location: selection.location + 1, length: 0))
        }
        let replacement = "[\(selected)](https://)"
        let urlStart = selection.location + (selected as NSString).length + 3
        return Edit(range: selection, replacement: replacement,
                    selection: NSRange(location: urlStart, length: ("https://" as NSString).length))
    }

    // MARK: Line breaks

    /// Markdown's line break: a backslash at the end of a line starts a new
    /// line within the paragraph (a plain Return only becomes a space).
    static let lineBreakTag = "\\"

    /// Replaces the selection with a line break: `\` and a new line, with
    /// the cursor at the start of that line. At the end of a line, only
    /// `\` is added and the line after joins it in the same paragraph.
    static func lineBreak(_ text: String, _ selection: NSRange) -> Edit {
        let ns = text as NSString
        let end = selection.location + selection.length
        let atLineEnd = end < ns.length && ns.character(at: end) == 10
        let replacement = atLineEnd ? lineBreakTag : lineBreakTag + "\n"
        let cursor = selection.location + (replacement as NSString).length + (atLineEnd ? 1 : 0)
        return Edit(range: selection, replacement: replacement, selection: NSRange(location: cursor, length: 0))
    }

    // MARK: Whole lines: headings, lists, quotes

    /// The full lines the selection touches (not counting a line the
    /// selection only reaches the very start of).
    static func lineRange(_ ns: NSString, _ selection: NSRange) -> NSRange {
        var sel = selection
        if sel.length > 0, sel.location + sel.length <= ns.length,
           sel.location + sel.length > 0, ns.character(at: sel.location + sel.length - 1) == 10 {
            sel.length -= 1
        }
        return ns.lineRange(for: sel)
    }

    private static let headingPrefix = try! NSRegularExpression(pattern: #"^#{1,6}[ \t]+"#)
    private static let listPrefix = try! NSRegularExpression(pattern: #"^(?:[-*+]|\d+[.)])[ \t]+"#)
    private static let quotePrefix = try! NSRegularExpression(pattern: #"^>[ \t]?"#)

    private static func strip(_ regex: NSRegularExpression, from line: String) -> String {
        let ns = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return line }
        return ns.substring(from: match.range.length)
    }

    private static func has(_ regex: NSRegularExpression, _ line: String) -> Bool {
        regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
    }

    /// Sets the heading level of the selected lines (0 = normal text).
    /// Choosing the level the lines already have makes them normal text.
    static func heading(_ text: String, _ selection: NSRange, level: Int) -> Edit {
        let marker = String(repeating: "#", count: level) + " "
        return transformLines(text, selection) { lines in
            let alreadyThisLevel = level > 0 && lines.allSatisfy { $0.isEmpty || $0.hasPrefix(marker) && !$0.hasPrefix(marker + "#") }
            return lines.map { line in
                guard !line.isEmpty else { return line }
                let plain = strip(headingPrefix, from: line)
                return alreadyThisLevel || level == 0 ? plain : marker + plain
            }
        }
    }

    /// Turns the selected lines into a bulleted or numbered list or a quote,
    /// or back into plain lines when they already are.
    static func toggleLines(_ text: String, _ selection: NSRange, style: LineStyle) -> Edit {
        transformLines(text, selection) { lines in
            let content = lines.filter { !$0.isEmpty }
            let isStyled: (String) -> Bool = { line in
                switch style {
                case .bullet: line.range(of: #"^[-*+][ \t]"#, options: .regularExpression) != nil
                case .numbered: line.range(of: #"^\d+[.)][ \t]"#, options: .regularExpression) != nil
                case .quote: line.hasPrefix(">")
                }
            }
            let remove = !content.isEmpty && content.allSatisfy(isStyled)
            var number = 0
            return lines.map { line in
                // An empty single line still gets the prefix, to start typing.
                guard !line.isEmpty || lines.count == 1 else { return line }
                if remove {
                    return style == .quote ? strip(quotePrefix, from: line) : strip(listPrefix, from: line)
                }
                let plain = style == .quote ? line : strip(listPrefix, from: strip(quotePrefix, from: line))
                switch style {
                case .bullet: return "- " + plain
                case .numbered:
                    number += 1
                    return "\(number). " + plain
                case .quote: return "> " + plain
                }
            }
        }
    }

    /// Applies `change` to the selected lines. A single cursor keeps its
    /// place in the text; a selection covers the changed lines afterwards.
    private static func transformLines(_ text: String, _ selection: NSRange, _ change: ([String]) -> [String]) -> Edit {
        let ns = text as NSString
        let range = lineRange(ns, selection)
        var block = ns.substring(with: range)
        let endsWithNewline = block.hasSuffix("\n")
        if endsWithNewline { block.removeLast() }
        let lines = block.components(separatedBy: "\n")
        var result = change(lines).joined(separator: "\n")
        let newLength = (result as NSString).length
        if endsWithNewline { result += "\n" }

        let newSelection: NSRange
        if selection.length == 0 && lines.count == 1 {
            // Keep the cursor at the same spot in the line's text.
            let delta = newLength - (block as NSString).length
            let offset = selection.location - range.location
            newSelection = NSRange(location: range.location + max(0, min(newLength, offset + delta)), length: 0)
        } else {
            newSelection = NSRange(location: range.location, length: newLength)
        }
        return Edit(range: range, replacement: result, selection: newSelection)
    }
}
