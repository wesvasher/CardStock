import AppKit
import Foundation
import Testing
@testable import CardStock

struct HeaderBarTests {
    typealias Header = SiteConfig.Header

    @Test func defaultsAddNothing() throws {
        var header = Header()
        #expect(SiteRenderer.headerBarStyle(header, appearance: .auto) == nil)
        header.mode = .fixed
        #expect(SiteRenderer.headerBarStyle(header, appearance: .auto) == nil)
        // Older site.json files have no bar settings.
        let old = try JSONDecoder().decode(Header.self, from: Data(#"{"mode":"fixed"}"#.utf8))
        #expect(old.bar.isDefault)
        #expect(old.bar.showsLine(.fixed) && !old.bar.showsLine(.scrolls))
    }

    @Test func lineBackgroundAndBlur() {
        var header = Header()
        header.mode = .fixed
        header.bar.line = false
        header.bar.blur = 0
        var css = SiteRenderer.headerBarStyle(header, appearance: .auto) ?? ""
        #expect(css.contains("border-bottom: none;"))
        #expect(css.contains("backdrop-filter: none;"))

        header.bar.background = .none
        #expect(SiteRenderer.headerBarStyle(header, appearance: .auto)?.contains("background: transparent;") == true)

        header.bar.background = .color
        header.bar.light = "#112233"
        header.bar.opacity = 80
        css = SiteRenderer.headerBarStyle(header, appearance: .auto) ?? ""
        #expect(css.contains("background: color-mix(in srgb, #112233 80%, transparent);"))
        // No dark color: the dark page color.
        #expect(css.contains("@media (prefers-color-scheme: dark) {\n  .site-bar, .site-bar.is-fixed { background: color-mix(in srgb, var(--bg) 80%, transparent); }"))
        header.bar.opacity = 100
        #expect(SiteRenderer.headerBarStyle(header, appearance: .light)?.contains("background: #112233;") == true)
        #expect(SiteRenderer.headerBarStyle(header, appearance: .light)?.contains("prefers-color-scheme") == false)

        // A bar that scrolls away can have a line; blur doesn't apply to it.
        var scrolling = Header()
        scrolling.bar.line = true
        scrolling.bar.blur = 5
        css = SiteRenderer.headerBarStyle(scrolling, appearance: .auto) ?? ""
        #expect(css.contains("border-bottom: 1px solid"))
        #expect(!css.contains("backdrop-filter"))
    }

    @Test func customLineIsKeptWhileOff() throws {
        var header = Header()
        header.mode = .fixed
        header.bar.lineWidth = 3
        header.bar.lineStyle = .dashed
        header.bar.lineLight = "#ff0000"
        var css = SiteRenderer.headerBarStyle(header, appearance: .auto) ?? ""
        #expect(css.contains("border-bottom: 3px dashed #ff0000;"))
        // No dark color: the theme's line color in dark mode.
        #expect(css.contains("@media (prefers-color-scheme: dark) {\n  .site-bar, .site-bar.is-fixed { border-bottom: 3px dashed color-mix(in srgb, var(--line) 70%, transparent); }"))

        header.bar.line = false
        css = SiteRenderer.headerBarStyle(header, appearance: .auto) ?? ""
        #expect(css.contains("border-bottom: none;"))
        #expect(!css.contains("dashed"))
        // The settings survive saving, ready for when the line comes back.
        let saved = try JSONDecoder().decode(Header.self, from: JSONEncoder().encode(header))
        #expect(saved.bar.lineWidth == 3 && saved.bar.lineStyle == .dashed && saved.bar.lineLight == "#ff0000")
        // A scrolling bar with custom line settings but no line gets nothing.
        var scrolling = Header()
        scrolling.bar.lineWidth = 2
        #expect(SiteRenderer.headerBarStyle(scrolling, appearance: .light) == nil)
    }

    @Test func menuButton() throws {
        var header = Header()
        #expect(SiteRenderer.menuButtonStyle(header, appearance: .auto) == nil)
        header.menuButton.light = "#ff0000"
        header.menuButton.size = 30
        var css = SiteRenderer.menuButtonStyle(header, appearance: .auto) ?? ""
        #expect(css.contains(".nav-toggle svg, .nav-close svg { width: 30px; height: 30px; }"))
        #expect(css.contains(".nav-toggle, .nav-toggle:hover, .nav-close, .nav-close:hover { color: #ff0000; }"))
        // No dark color: the link color in dark mode.
        #expect(css.contains("@media (prefers-color-scheme: dark) {\n.nav-toggle, .nav-close { color: var(--nav-link); }"))
        header.menuButton.dark = "#00ff00"
        css = SiteRenderer.menuButtonStyle(header, appearance: .dark) ?? ""
        #expect(css.contains("color: #00ff00;") && !css.contains("#ff0000"))
        // Nothing without the phone menu.
        header.mobileMenu = false
        #expect(SiteRenderer.menuButtonStyle(header, appearance: .auto) == nil)

        // Older site.json files keep three lines.
        #expect(try JSONDecoder().decode(Header.self, from: Data("{}".utf8)).menuButton.isDefault)
        // Every icon is valid SVG (the settings draw them from it too).
        for icon in Header.MenuButton.Icon.allCases {
            let svg = icon.svg.replacingOccurrences(of: "<svg ", with: #"<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" "#)
            #expect(NSImage(data: Data(svg.utf8))?.isValid == true, "\(icon)")
        }
    }

    @Test func pagesGetTheMenuIcon() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "cardstock-menu-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try StarterSite.create(at: dir, title: "Menu")
        var site = try Site.load(from: dir)
        site.config.nav = [.init(title: "About", url: "/pages/about/")]
        var html = try SiteRenderer(site: site).render(path: "/") ?? ""
        #expect(html.contains(#"<line x1="4" x2="20" y1="6" y2="6"/>"#))
        site.config.header.menuButton.icon = .dots
        html = try SiteRenderer(site: site).render(path: "/") ?? ""
        #expect(html.contains(#"aria-controls="nav-overlay"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="1"/>"#))
        #expect(!html.contains(#"<line x1="4" x2="20" y1="6" y2="6"/>"#))
        // The ✕ is moved onto the menu button, once per page.
        #expect(html.components(separatedBy: "toggle.getBoundingClientRect()").count == 2)
        site.config.header.mobileMenu = false
        html = try SiteRenderer(site: site).render(path: "/") ?? ""
        #expect(!html.contains("toggle.getBoundingClientRect()"))
    }

    @Test func pagesGetTheStyle() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "cardstock-bar-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try StarterSite.create(at: dir, title: "Bar")
        var site = try Site.load(from: dir)
        site.config.header.bar.background = .none
        let html = try SiteRenderer(site: site).render(path: "/") ?? ""
        #expect(html.contains(".site-bar, .site-bar.is-fixed { background: transparent; }"))
    }
}
