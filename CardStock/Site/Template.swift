import Foundation

/// A value passed to a template.
enum TemplateValue: Sendable, Equatable {
    case string(String)
    case bool(Bool)
    case list([TemplateValue])
    case dict([String: TemplateValue])

    var isTruthy: Bool {
        switch self {
        case .string(let s): !s.isEmpty
        case .bool(let b): b
        case .list(let l): !l.isEmpty
        case .dict(let d): !d.isEmpty
        }
    }

    var text: String {
        switch self {
        case .string(let s): s
        case .bool(let b): b ? "true" : "false"
        case .list(let l): l.map(\.text).joined(separator: ", ")
        case .dict: ""
        }
    }

    subscript(key: String) -> TemplateValue? {
        if case .dict(let d) = self { d[key] } else { nil }
    }
}

struct TemplateError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

/// A parsed theme template. See docs/site-format.md for the syntax.
struct Template: Sendable {
    private indirect enum Node: Sendable {
        case text(String)
        case variable(String, raw: Bool)
        case ifBlock(String, then: [Node], otherwise: [Node])
        case each(String, body: [Node])
    }

    private let nodes: [Node]
    let name: String

    init(_ source: String, name: String = "template") throws {
        self.name = name
        var parser = Parser(source: source, name: name)
        nodes = try parser.parseAll()
    }

    func render(_ context: TemplateValue) -> String {
        var out = ""
        Self.render(nodes, scopes: [context], into: &out)
        return out
    }

    // MARK: - Rendering

    private static func render(_ nodes: [Node], scopes: [TemplateValue], into out: inout String) {
        for node in nodes {
            switch node {
            case .text(let s):
                out += s
            case .variable(let path, let raw):
                let value = lookup(path, in: scopes)?.text ?? ""
                out += raw ? value : escapeHTML(value)
            case .ifBlock(let path, let then, let otherwise):
                let truthy = lookup(path, in: scopes)?.isTruthy ?? false
                render(truthy ? then : otherwise, scopes: scopes, into: &out)
            case .each(let path, let body):
                guard case .list(let items) = lookup(path, in: scopes) else { continue }
                for item in items {
                    render(body, scopes: scopes + [item], into: &out)
                }
            }
        }
    }

    private static func lookup(_ path: String, in scopes: [TemplateValue]) -> TemplateValue? {
        let parts = path.split(separator: ".").map(String.init)
        guard let head = parts.first else { return nil }
        var value: TemplateValue?
        if head == "this" {
            value = scopes.last
        } else {
            value = scopes.reversed().lazy.compactMap { $0[head] }.first
        }
        for part in parts.dropFirst() {
            value = value?[part]
        }
        return value
    }

    // MARK: - Parsing

    private struct Parser {
        let source: String
        let name: String
        var index: String.Index

        init(source: String, name: String) {
            self.source = source
            self.name = name
            self.index = source.startIndex
        }

        mutating func parseAll() throws -> [Node] {
            let (nodes, end) = try parseNodes()
            if let end { throw error("unexpected {{\(end)}}") }
            return nodes
        }

        /// Parses until the end of input or a closing tag, which it returns.
        private mutating func parseNodes() throws -> ([Node], String?) {
            var nodes: [Node] = []
            while index < source.endIndex {
                guard let open = source.range(of: "{{", range: index..<source.endIndex) else {
                    nodes.append(.text(String(source[index...])))
                    index = source.endIndex
                    break
                }
                if open.lowerBound > index {
                    nodes.append(.text(String(source[index..<open.lowerBound])))
                }
                let raw = source[open.upperBound...].hasPrefix("{")
                let contentStart = raw ? source.index(after: open.upperBound) : open.upperBound
                let closer = raw ? "}}}" : "}}"
                guard let close = source.range(of: closer, range: contentStart..<source.endIndex) else {
                    throw error("missing \(closer)")
                }
                let tag = source[contentStart..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                index = close.upperBound

                if raw {
                    nodes.append(.variable(tag, raw: true))
                } else if tag.hasPrefix("#if ") {
                    let path = tag.dropFirst(4).trimmingCharacters(in: .whitespaces)
                    let (then, end1) = try parseNodes()
                    var otherwise: [Node] = []
                    var end = end1
                    if end1 == "else" {
                        (otherwise, end) = try parseNodes()
                    }
                    guard end == "/if" else { throw error("{{#if \(path)}} is missing {{/if}}") }
                    nodes.append(.ifBlock(path, then: then, otherwise: otherwise))
                } else if tag.hasPrefix("#each ") {
                    let path = tag.dropFirst(6).trimmingCharacters(in: .whitespaces)
                    let (body, end) = try parseNodes()
                    guard end == "/each" else { throw error("{{#each \(path)}} is missing {{/each}}") }
                    nodes.append(.each(path, body: body))
                } else if tag == "else" || tag == "/if" || tag == "/each" {
                    return (nodes, tag)
                } else if tag.hasPrefix("#") || tag.hasPrefix("/") {
                    throw error("unknown tag {{\(tag)}}")
                } else {
                    nodes.append(.variable(tag, raw: false))
                }
            }
            return (nodes, nil)
        }

        private func error(_ message: String) -> TemplateError {
            let line = source[..<index].filter { $0 == "\n" }.count + 1
            return TemplateError(message: "\(name), line \(line): \(message)")
        }
    }
}

func escapeHTML(_ s: String) -> String {
    var out = ""
    out.reserveCapacity(s.count)
    for ch in s {
        switch ch {
        case "&": out += "&amp;"
        case "<": out += "&lt;"
        case ">": out += "&gt;"
        case "\"": out += "&quot;"
        case "'": out += "&#39;"
        default: out.append(ch)
        }
    }
    return out
}
