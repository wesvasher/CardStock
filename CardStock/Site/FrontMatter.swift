import Foundation

/// A value in a content file's header.
enum FrontMatterValue: Equatable, Sendable {
    case string(String)
    case bool(Bool)
    case list([String])
}

/// The `---` header at the top of a content file. Keeps keys in file order
/// so saving a file doesn't reshuffle it. Supports a small YAML subset:
/// `key: value`, where a value is text, `true`/`false`, or `[a, b]`.
struct FrontMatter: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        var key: String
        var value: FrontMatterValue
    }

    private(set) var entries: [Entry] = []

    subscript(key: String) -> FrontMatterValue? {
        get { entries.first { $0.key == key }?.value }
        set {
            if let i = entries.firstIndex(where: { $0.key == key }) {
                if let newValue { entries[i].value = newValue } else { entries.remove(at: i) }
            } else if let newValue {
                entries.append(Entry(key: key, value: newValue))
            }
        }
    }

    func string(_ key: String) -> String? {
        switch self[key] {
        case .string(let s): s
        case .bool(let b): b ? "true" : "false"
        case .list(let l): l.joined(separator: ", ")
        case nil: nil
        }
    }

    func bool(_ key: String) -> Bool {
        switch self[key] {
        case .bool(let b): b
        case .string(let s): s.lowercased() == "true" || s.lowercased() == "yes"
        default: false
        }
    }

    func list(_ key: String) -> [String] {
        switch self[key] {
        case .list(let l): l
        case .string(let s) where !s.isEmpty:
            s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        default: []
        }
    }

    /// Sets a text value, removing the key when the text is empty.
    mutating func setString(_ key: String, _ value: String) {
        self[key] = value.isEmpty ? nil : .string(value)
    }

    // MARK: - Parsing

    /// Splits a file into its header and Markdown body. A file with no header
    /// returns an empty header and the whole text as the body.
    static func parse(_ text: String) -> (FrontMatter, body: String) {
        let text = text.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return (FrontMatter(), text) }

        var fm = FrontMatter()
        for line in lines[1..<end] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = trimmed[..<colon].trimmingCharacters(in: .whitespaces)
            let raw = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            fm[key] = parseValue(raw)
        }

        lines.removeSubrange(0...end)
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeFirst()
        }
        return (fm, lines.joined(separator: "\n"))
    }

    private static func parseValue(_ raw: String) -> FrontMatterValue {
        if raw.hasPrefix("[") && raw.hasSuffix("]") {
            let inner = raw.dropFirst().dropLast()
            return .list(splitList(String(inner)).map(unquote).filter { !$0.isEmpty })
        }
        switch raw.lowercased() {
        case "true", "yes": return .bool(true)
        case "false", "no": return .bool(false)
        default: return .string(unquote(raw))
        }
    }

    /// Splits on commas that aren't inside quotes.
    private static func splitList(_ s: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var quote: Character?
        for ch in s {
            if let q = quote {
                current.append(ch)
                if ch == q { quote = nil }
            } else if ch == "\"" || ch == "'" {
                quote = ch
                current.append(ch)
            } else if ch == "," {
                parts.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        parts.append(current)
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func unquote(_ s: String) -> String {
        let s = s.trimmingCharacters(in: .whitespaces)
        guard s.count >= 2, let first = s.first, first == s.last, first == "\"" || first == "'" else { return s }
        let inner = String(s.dropFirst().dropLast())
        if first == "'" { return inner.replacingOccurrences(of: "''", with: "'") }
        var out = ""
        var escaping = false
        for ch in inner {
            if escaping {
                out.append(ch == "n" ? "\n" : ch)
                escaping = false
            } else if ch == "\\" {
                escaping = true
            } else {
                out.append(ch)
            }
        }
        return out
    }

    // MARK: - Writing

    /// Joins a header and body back into file text.
    static func serialize(_ fm: FrontMatter, body: String) -> String {
        var out = "---\n"
        for entry in fm.entries {
            out += "\(entry.key): \(format(entry.value))\n"
        }
        out += "---\n\n"
        out += body
        if !out.hasSuffix("\n") { out += "\n" }
        return out
    }

    private static func format(_ value: FrontMatterValue) -> String {
        switch value {
        case .bool(let b): return b ? "true" : "false"
        case .string(let s): return quoteIfNeeded(s, inList: false)
        case .list(let l): return "[" + l.map { quoteIfNeeded($0, inList: true) }.joined(separator: ", ") + "]"
        }
    }

    private static func quoteIfNeeded(_ s: String, inList: Bool) -> String {
        let special: Set<Character> = ["[", "{", "\"", "'", "#", "&", "*", "!", "|", ">", "%", "@", "`", "-", "?"]
        let reserved = ["true", "false", "yes", "no", "null", "~"]
        let needs = s.isEmpty
            || special.contains(s.first!)
            || s.first!.isWhitespace || s.last!.isWhitespace
            || s.contains(": ") || s.contains(" #") || s.contains("\n")
            || reserved.contains(s.lowercased())
            || (inList && (s.contains(",") || s.contains("]")))
        guard needs else { return s }
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}
