import AppKit

/// Styles Markdown text in the editor as it's typed: larger headings, bold
/// and italic text, colored links and list markers, dimmed symbols and
/// monospaced code. Only the look changes; the text stays plain Markdown.
@MainActor
enum MarkdownStyler {
    static let baseSize: CGFloat = 14

    static var baseFont: NSFont { .systemFont(ofSize: baseSize) }
    static var codeFont: NSFont { .monospacedSystemFont(ofSize: baseSize - 1, weight: .regular) }

    static var baseAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 2
        return [.font: baseFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
    }

    private static let symbolColor = NSColor.tertiaryLabelColor
    private static let codeBackground = NSColor.quaternaryLabelColor.withAlphaComponent(0.12)

    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static let fence = regex(#"^(```|~~~)[^\n]*\n[\s\S]*?(?:^\1[ \t]*$|\z)"#, [.anchorsMatchLines])
    private static let heading = regex(#"^(#{1,6})([ \t]+)(.*)$"#, [.anchorsMatchLines])
    private static let quote = regex(#"^(>[ \t]?)(.*)$"#, [.anchorsMatchLines])
    private static let listMarker = regex(#"^[ \t]*([-*+]|\d+[.)])[ \t]+"#, [.anchorsMatchLines])
    private static let rule = regex(#"^[ \t]*([-*_])(?:[ \t]*\1){2,}[ \t]*$"#, [.anchorsMatchLines])
    private static let inlineCode = regex(#"`[^`\n]+`"#)
    private static let bold = regex(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private static let italicStar = regex(#"(?<![*\w])\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?![*\w])"#)
    private static let italicUnderscore = regex(#"(?<![\w_])_(?=[^\s_])(.+?)(?<=[^\s_])_(?![\w_])"#)
    private static let strike = regex(#"~~(?=\S)(.+?)(?<=\S)~~"#)
    private static let link = regex(#"(?<!!)\[((?:[^\[\]\n]|!\[[^\]\n]*\]\([^)\n]*\))+)\]\(([^)\n]*)\)"#)
    private static let small = regex(#"(<small>)([\s\S]*?)(</small>)"#, [.caseInsensitive])
    /// Section breaks (for layouts) and boxes (mailing list, search).
    private static let sectionBreak = regex(#"^[ \t]*<!--[ \t]*(?:section|newsletter|search)[ \t]*-->[ \t]*$"#, [.anchorsMatchLines, .caseInsensitive])
    private static let image = regex(#"!\[([^\]\n]*)\]\(([^)\n]*)\)"#)

    /// Restyles all of `storage`.
    static func style(_ storage: NSTextStorage) {
        let text = storage.string
        let all = NSRange(location: 0, length: (text as NSString).length)
        storage.setAttributes(baseAttributes, range: all)
        guard all.length > 0 else { return }

        // Code first; nothing else is styled inside it.
        var code: [NSRange] = []
        for m in fence.matches(in: text, range: all) {
            storage.addAttributes([.font: codeFont, .backgroundColor: codeBackground,
                                   .foregroundColor: NSColor.secondaryLabelColor], range: m.range)
            code.append(m.range)
        }
        func inCode(_ r: NSRange) -> Bool { code.contains { NSIntersectionRange($0, r).length > 0 } }

        for m in inlineCode.matches(in: text, range: all) where !inCode(m.range) {
            storage.addAttributes([.font: codeFont, .backgroundColor: codeBackground], range: m.range)
            dim(storage, NSRange(location: m.range.location, length: 1))
            dim(storage, NSRange(location: NSMaxRange(m.range) - 1, length: 1))
            code.append(m.range)
        }

        for m in heading.matches(in: text, range: all) where !inCode(m.range) {
            let level = m.range(at: 1).length
            let scale: CGFloat = [1.6, 1.35, 1.18, 1.05, 1.0, 1.0][level - 1]
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: baseSize * scale, weight: .bold), range: m.range)
            dim(storage, NSRange(location: m.range.location, length: m.range(at: 1).length + m.range(at: 2).length))
        }

        for m in quote.matches(in: text, range: all) where !inCode(m.range) {
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: m.range(at: 2))
            addTrait(.italicFontMask, storage, m.range(at: 2))
            storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: m.range(at: 1))
        }

        for m in rule.matches(in: text, range: all) where !inCode(m.range) {
            dim(storage, m.range)
        }

        // Section breaks and newsletter lines: an accent-colored band.
        for m in sectionBreak.matches(in: text, range: all) where !inCode(m.range) {
            storage.addAttributes([.foregroundColor: NSColor.controlAccentColor,
                                   .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.1),
                                   .font: NSFont.monospacedSystemFont(ofSize: baseSize - 2, weight: .semibold)],
                                  range: m.range)
        }

        for m in listMarker.matches(in: text, range: all) where !inCode(m.range) {
            storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: m.range(at: 1))
            addTrait(.boldFontMask, storage, m.range(at: 1))
        }

        for m in bold.matches(in: text, range: all) where !inCode(m.range) {
            addTrait(.boldFontMask, storage, m.range)
            dimMarkers(storage, m.range, length: 2)
        }
        for pattern in [italicStar, italicUnderscore] {
            for m in pattern.matches(in: text, range: all) where !inCode(m.range) {
                addTrait(.italicFontMask, storage, m.range)
                dimMarkers(storage, m.range, length: 1)
            }
        }
        for m in strike.matches(in: text, range: all) where !inCode(m.range) {
            storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                   .foregroundColor: NSColor.secondaryLabelColor], range: m.range)
            dimMarkers(storage, m.range, length: 2)
        }

        // Links: the text in the link color, the brackets and address dimmed.
        for m in link.matches(in: text, range: all) where !inCode(m.range) {
            let textRange = m.range(at: 1)
            if !(text as NSString).substring(with: textRange).hasPrefix("![") {
                storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: textRange)
            }
            dim(storage, NSRange(location: m.range.location, length: 1))
            dim(storage, NSRange(location: NSMaxRange(textRange), length: NSMaxRange(m.range) - NSMaxRange(textRange)))
        }

        // Fine print: smaller and gray, with the tags dimmed.
        for m in small.matches(in: text, range: all) where !inCode(m.range) {
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: m.range(at: 2))
            storage.enumerateAttribute(.font, in: m.range) { value, sub, _ in
                guard let font = value as? NSFont else { return }
                let smaller = NSFontManager.shared.convert(font, toSize: (font.pointSize * 0.85).rounded())
                storage.addAttribute(.font, value: smaller, range: sub)
            }
            dim(storage, m.range(at: 1))
            dim(storage, m.range(at: 3))
        }

        // Images: the description stays readable, the rest is dimmed.
        for m in image.matches(in: text, range: all) where !inCode(m.range) {
            dim(storage, m.range)
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: m.range(at: 1))
            addTrait(.italicFontMask, storage, m.range(at: 1))
        }
    }

    private static func dim(_ storage: NSTextStorage, _ range: NSRange) {
        guard range.length > 0 else { return }
        storage.addAttribute(.foregroundColor, value: symbolColor, range: range)
    }

    private static func dimMarkers(_ storage: NSTextStorage, _ range: NSRange, length: Int) {
        dim(storage, NSRange(location: range.location, length: length))
        dim(storage, NSRange(location: NSMaxRange(range) - length, length: length))
    }

    /// Adds bold or italic to whatever fonts the range already has, so a
    /// bold word in a heading keeps the heading's size.
    private static func addTrait(_ trait: NSFontTraitMask, _ storage: NSTextStorage, _ range: NSRange) {
        guard range.length > 0 else { return }
        let manager = NSFontManager.shared
        storage.enumerateAttribute(.font, in: range) { value, sub, _ in
            guard let font = value as? NSFont else { return }
            storage.addAttribute(.font, value: manager.convert(font, toHaveTrait: trait), range: sub)
        }
    }
}
