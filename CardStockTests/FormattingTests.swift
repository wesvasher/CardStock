import AppKit
import Foundation
import Testing
@testable import CardStock

struct FormattingTests {
    typealias F = MarkdownFormatting

    /// Applies an edit and returns the new text and selected text.
    private func run(_ text: String, _ edit: F.Edit) -> (String, NSRange) {
        ((text as NSString).replacingCharacters(in: edit.range, with: edit.replacement), edit.selection)
    }

    @Test func boldWrapsAndUnwraps() {
        var (text, sel) = run("hello world", F.toggleWrap("hello world", NSRange(location: 6, length: 5), marker: "**"))
        #expect(text == "hello **world**")
        #expect(sel == NSRange(location: 8, length: 5))
        (text, sel) = run(text, F.toggleWrap(text, sel, marker: "**"))
        #expect(text == "hello world")
        #expect(sel == NSRange(location: 6, length: 5))
        // Markers included in the selection.
        (text, _) = run("a **b** c", F.toggleWrap("a **b** c", NSRange(location: 2, length: 5), marker: "**"))
        #expect(text == "a b c")
    }

    @Test func italicAndBoldDontConfuseEachOther() {
        // Italic inside bold adds a star rather than removing one.
        var (text, sel) = run("x **word**", F.toggleWrap("x **word**", NSRange(location: 4, length: 4), marker: "*"))
        #expect(text == "x ***word***")
        (text, sel) = run(text, F.toggleWrap(text, sel, marker: "*"))
        #expect(text == "x **word**")
        _ = sel
    }

    @Test func cursorUsesTheWordOrInsertsMarkers() {
        let (text, sel) = run("hello world", F.toggleWrap("hello world", NSRange(location: 8, length: 0), marker: "**"))
        #expect(text == "hello **world**")
        #expect(sel == NSRange(location: 8, length: 5))

        var (empty, cursor) = run("hi ", F.toggleWrap("hi ", NSRange(location: 3, length: 0), marker: "**"))
        #expect(empty == "hi ****")
        #expect(cursor == NSRange(location: 5, length: 0))
        (empty, cursor) = run(empty, F.toggleWrap(empty, cursor, marker: "**"))
        #expect(empty == "hi ")
        #expect(cursor == NSRange(location: 3, length: 0))
    }

    @Test func links() {
        let (text, sel) = run("see docs", F.link("see docs", NSRange(location: 4, length: 4)))
        #expect(text == "see [docs](https://)")
        #expect((text as NSString).substring(with: sel) == "https://")

        let (url, cursor) = run("https://x.com", F.link("https://x.com", NSRange(location: 0, length: 13)))
        #expect(url == "[](https://x.com)")
        #expect(cursor == NSRange(location: 1, length: 0))

        let (blank, placeholder) = run("", F.link("", NSRange(location: 0, length: 0)))
        #expect(blank == "[link text](https://)")
        #expect((blank as NSString).substring(with: placeholder) == "link text")
    }

    @Test func headings() {
        var (text, sel) = run("Title\nnext", F.heading("Title\nnext", NSRange(location: 2, length: 0), level: 2))
        #expect(text == "## Title\nnext")
        #expect(sel == NSRange(location: 5, length: 0))
        (text, _) = run(text, F.heading(text, sel, level: 3))
        #expect(text == "### Title\nnext")
        (text, _) = run(text, F.heading(text, NSRange(location: 1, length: 0), level: 3))
        #expect(text == "Title\nnext")
    }

    @Test func listsAndQuotes() {
        var (text, sel) = run("a\nb\n", F.toggleLines("a\nb\n", NSRange(location: 0, length: 4), style: .bullet))
        #expect(text == "- a\n- b\n")
        (text, sel) = run(text, F.toggleLines(text, sel, style: .numbered))
        #expect(text == "1. a\n2. b\n")
        (text, _) = run(text, F.toggleLines(text, sel, style: .numbered))
        #expect(text == "a\nb\n")

        let (quote, _) = run("x", F.toggleLines("x", NSRange(location: 0, length: 0), style: .quote))
        #expect(quote == "> x")

        let (start, cursor) = run("", F.toggleLines("", NSRange(location: 0, length: 0), style: .bullet))
        #expect(start == "- ")
        #expect(cursor == NSRange(location: 2, length: 0))
    }

    @Test func finePrint() {
        let tag = (open: "<small>", close: "</small>")
        var (text, sel) = run("Photo by Ann", F.toggleTag("Photo by Ann", NSRange(location: 0, length: 12), open: tag.open, close: tag.close))
        #expect(text == "<small>Photo by Ann</small>")
        #expect((text as NSString).substring(with: sel) == "Photo by Ann")
        (text, _) = run(text, F.toggleTag(text, sel, open: tag.open, close: tag.close))
        #expect(text == "Photo by Ann")

        let (empty, cursor) = run("", F.toggleTag("", NSRange(location: 0, length: 0), open: tag.open, close: tag.close))
        #expect(empty == "<small></small>")
        #expect(cursor == NSRange(location: 7, length: 0))
    }

    @Test func finePrintIsRenderedAsHTML() {
        let html = SiteRenderer.markdownToHTML("![A](/a.jpg)\n<small>Photo by Ann</small>")
        #expect(html.contains("<small>Photo by Ann</small>"))
    }

    @MainActor @Test func stylerFormatsWithoutChangingText() throws {
        let text = "## Big\nSome **bold** and `code`.\n"
        let storage = NSTextStorage(string: text)
        MarkdownStyler.style(storage)
        #expect(storage.string == text)
        let heading = try #require(storage.attribute(.font, at: 4, effectiveRange: nil) as? NSFont)
        #expect(heading.pointSize > MarkdownStyler.baseSize)
        let bold = try #require(storage.attribute(.font, at: 15, effectiveRange: nil) as? NSFont)
        #expect(bold.fontDescriptor.symbolicTraits.contains(.bold))
        let plain = try #require(storage.attribute(.font, at: 8, effectiveRange: nil) as? NSFont)
        #expect(!plain.fontDescriptor.symbolicTraits.contains(.bold))
    }
}

struct PreviewAddressTests {
    @Test func showsTheBuiltFile() {
        #expect(PreviewNavigator.builtFile(for: "/") == "public/index.html")
        #expect(PreviewNavigator.builtFile(for: "/posts/trip/") == "public/posts/trip/index.html")
        #expect(PreviewNavigator.builtFile(for: "/feed.xml") == "public/feed.xml")
        #expect(PreviewNavigator.builtFile(for: "/media/a.jpg") == "public/media/a.jpg")
    }
}
