import Foundation

extension SiteConfig.Header {
    /// The button that opens the links on phones (`mobileMenu`): its icon,
    /// color and size. The defaults are the theme's own.
    struct MenuButton: Codable, Equatable, Sendable {
        enum Icon: String, Codable, CaseIterable, Sendable, Identifiable {
            case lines, twoLines, staggered, dots, dotsVertical, grid

            var id: Self { self }

            var name: String {
                switch self {
                case .lines: "Three lines"
                case .twoLines: "Two lines"
                case .staggered: "Staggered lines"
                case .dots: "Dots"
                case .dotsVertical: "Vertical dots"
                case .grid: "Grid"
                }
            }

            /// The shapes inside a 24 × 24 Lucide-style SVG.
            var inner: String {
                switch self {
                case .lines:
                    #"<line x1="4" x2="20" y1="12" y2="12"/><line x1="4" x2="20" y1="6" y2="6"/><line x1="4" x2="20" y1="18" y2="18"/>"#
                case .twoLines:
                    #"<line x1="4" x2="20" y1="9" y2="9"/><line x1="4" x2="20" y1="15" y2="15"/>"#
                case .staggered:
                    #"<line x1="4" x2="20" y1="6" y2="6"/><line x1="4" x2="16" y1="12" y2="12"/><line x1="4" x2="12" y1="18" y2="18"/>"#
                case .dots:
                    #"<circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/><circle cx="5" cy="12" r="1"/>"#
                case .dotsVertical:
                    #"<circle cx="12" cy="12" r="1"/><circle cx="12" cy="5" r="1"/><circle cx="12" cy="19" r="1"/>"#
                case .grid:
                    #"<rect width="7" height="7" x="3" y="3" rx="1"/><rect width="7" height="7" x="14" y="3" rx="1"/><rect width="7" height="7" x="14" y="14" rx="1"/><rect width="7" height="7" x="3" y="14" rx="1"/>"#
                }
            }

            /// The icon as inline SVG in the button's text color.
            var svg: String {
                #"<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">"#
                    + inner + "</svg>"
            }
        }

        var icon = Icon.lines
        /// `#rrggbb` per appearance; empty uses the top bar's link color.
        var light = ""
        var dark = ""
        /// Icon size in pixels (the theme's is 1.6rem, about 26).
        var size: Double = 26

        static let themeSize: Double = 26
        var isDefault: Bool { self == MenuButton() }

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = MenuButton()
            icon = (try? c.decodeIfPresent(Icon.self, forKey: .icon)) ?? d.icon
            light = try c.decodeIfPresent(String.self, forKey: .light) ?? ""
            dark = try c.decodeIfPresent(String.self, forKey: .dark) ?? ""
            size = try c.decodeIfPresent(Double.self, forKey: .size) ?? d.size
        }
    }
}

extension SiteRenderer {
    /// CSS for the menu button's color and size, or nil for the theme's.
    static func menuButtonStyle(_ header: SiteConfig.Header, appearance: ThemeSettings.Appearance) -> String? {
        let button = header.menuButton
        guard header.mobileMenu, !button.isDefault else { return nil }
        var css = ""
        if button.size != SiteConfig.Header.MenuButton.themeSize {
            let size = ratio(min(max(button.size, 12), 48))
            css += ".nav-toggle svg, .nav-close svg { width: \(size)px; height: \(size)px; }\n"
        }
        func color(_ hex: String) -> String? {
            hex.trimmingCharacters(in: .whitespaces).isEmpty ? nil
                : ".nav-toggle, .nav-toggle:hover, .nav-close, .nav-close:hover { color: \(ThemeSettings.sanitizeColor(hex)); }\n.nav-toggle:hover, .nav-close:hover { opacity: 0.75; }\n"
        }
        switch appearance {
        case .light: css += color(button.light) ?? ""
        case .dark: css += color(button.dark) ?? ""
        case .auto:
            css += color(button.light) ?? ""
            if let dark = color(button.dark) {
                css += "@media (prefers-color-scheme: dark) {\n" + dark + "}\n"
            } else if !button.light.isEmpty {
                // Back to the link color in dark mode.
                css += "@media (prefers-color-scheme: dark) {\n.nav-toggle, .nav-close { color: var(--nav-link); }\n.nav-toggle:hover, .nav-close:hover { color: var(--nav-hover); opacity: 1; }\n}\n"
            }
        }
        return css.isEmpty ? nil : "<style>\n" + css + "</style>\n"
    }

    /// Puts the menu's ✕ exactly where the menu button is, so it takes the
    /// button's place wherever the bar puts it (logo side, padding, a shrunk
    /// bar). Added to every page with a phone menu, so older themes get it too.
    static let closeButtonScript = """
    <script>
    (function () {
      var toggle = document.querySelector(".nav-toggle");
      var close = document.querySelector(".nav-overlay .nav-close");
      if (!toggle || !close) return;
      function place() {
        var r = toggle.getBoundingClientRect();
        if (!r.width) return;
        var s = close.style;
        s.position = "fixed"; s.margin = "0"; s.right = "auto"; s.bottom = "auto";
        s.top = r.top + "px"; s.left = r.left + "px";
        s.width = r.width + "px"; s.height = r.height + "px";
      }
      toggle.addEventListener("click", place);
      window.addEventListener("resize", function () { if (document.documentElement.classList.contains("nav-open")) place(); });
    })();
    </script>

    """

    static func insertCloseButtonScript(into html: String) -> String {
        guard html.contains("nav-toggle"), html.contains("nav-close"),
              let end = html.range(of: "</body>", options: [.caseInsensitive, .backwards]) else { return html }
        var html = html
        html.insert(contentsOf: closeButtonScript, at: end.lowerBound)
        return html
    }

    /// Puts the chosen icon in the menu button (base.html draws three lines).
    static func insertMenuIcon(_ header: SiteConfig.Header, into html: String) -> String {
        guard header.menuButton.icon != .lines, html.contains("nav-toggle"),
              let regex = try? NSRegularExpression(pattern: #"(<button class="nav-toggle"[^>]*>)[\s\S]*?(</button>)"#) else { return html }
        let template = "$1" + NSRegularExpression.escapedTemplate(for: header.menuButton.icon.svg) + "$2"
        return regex.stringByReplacingMatches(in: html, range: NSRange(html.startIndex..., in: html), withTemplate: template)
    }
}
