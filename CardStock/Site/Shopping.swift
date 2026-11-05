import Foundation

extension SiteConfig {
    /// How the site sells things (`shopping` in site.json), edited in
    /// Configuration → Shopping. For now the only checkout service is Stripe
    /// Payment Links: a link per product that opens Stripe's checkout page,
    /// shown on the site as a Buy button.
    struct Shopping: Codable, Equatable, Sendable {
        /// The checkout service. More may come (carts like Snipcart or
        /// Shopify Buy Button), each with its own settings.
        enum Provider: String, Codable, CaseIterable, Sendable {
            case none
            case stripePaymentLinks = "stripe-payment-links"

            var title: String {
                switch self {
                case .none: "None"
                case .stripePaymentLinks: "Stripe Payment Links"
                }
            }

            var summary: String {
                switch self {
                case .none: "No checkout. Shop items can still link to a checkout page of your own."
                case .stripePaymentLinks: "A link per product from Stripe. Each one is a Buy button that opens Stripe's secure checkout page. No shopping cart, no code."
                }
            }

            var systemImage: String {
                switch self {
                case .none: "nosign"
                case .stripePaymentLinks: "link.badge.plus"
                }
            }
        }

        var provider = Provider.none
        /// What new Buy buttons say.
        var buttonLabel = "Buy Now"

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // A service this version doesn't know (from a newer CardStock) reads as none.
            provider = (try? c.decodeIfPresent(Provider.self, forKey: .provider)) ?? Provider.none
            buttonLabel = try c.decodeIfPresent(String.self, forKey: .buttonLabel) ?? "Buy Now"
        }

        var usesPaymentLinks: Bool { provider == .stripePaymentLinks }

        /// The button text, or Buy Now when it's empty.
        var shownButtonLabel: String {
            let label = buttonLabel.trimmingCharacters(in: .whitespaces)
            return label.isEmpty ? "Buy Now" : label
        }
    }
}

/// A Buy button placed in a page's Markdown with a line of its own:
/// `<!-- buy https://buy.stripe.com/abc123 "Buy the print" -->`. The link
/// opens the checkout page (a Stripe Payment Link) in a new tab. Lines in
/// code blocks are left alone.
enum BuyButton {
    static let defaultLabel = "Buy Now"

    /// The line for a button. Quotes and `--` can't be in the text, since
    /// they'd end it (or the comment) early.
    static func marker(link: String, label: String) -> String {
        let text = cleanLabel(label)
        let link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "<!-- buy \(link) -->" : "<!-- buy \(link) \"\(text)\" -->"
    }

    static func cleanLabel(_ label: String) -> String {
        label.replacingOccurrences(of: "\"", with: "”")
            .replacingOccurrences(of: "--", with: "–")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private static let pattern = try! NSRegularExpression(
        pattern: #"^<!--\s*buy\s+(\S+?)(?:\s+"([^"]*)")?\s*-->$"#, options: .caseInsensitive)

    /// The link and text in a Buy button line, if it is one.
    static func parse(_ line: String) -> (link: String, label: String)? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.lowercased().hasPrefix("<!--"),
              let match = pattern.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
              let linkRange = Range(match.range(at: 1), in: t) else { return nil }
        let link = String(t[linkRange])
        guard isWebLink(link) else { return nil }
        let label = Range(match.range(at: 2), in: t).map { String(t[$0]).trimmingCharacters(in: .whitespaces) } ?? ""
        return (link, label.isEmpty ? defaultLabel : label)
    }

    /// An http or https address with no spaces.
    static func isWebLink(_ link: String) -> Bool {
        guard let url = URL(string: link), let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "https" || scheme == "http") && url.host() != nil && !link.contains(where: \.isWhitespace)
    }

    /// Whether a link is one of Stripe's Payment Links (`buy.stripe.com`).
    static func isStripeLink(_ link: String) -> Bool {
        guard let host = URL(string: link.trimmingCharacters(in: .whitespaces))?.host()?.lowercased() else { return false }
        return host == "buy.stripe.com" || host.hasSuffix(".stripe.com") && host.hasPrefix("buy.")
    }

    /// Turns every Buy button line outside code blocks into the button.
    static func markPlaces(in markdown: String) -> String {
        guard markdown.range(of: "buy", options: .caseInsensitive) != nil, markdown.contains("<!--") else { return markdown }
        return PageWidget.eachLine(of: markdown) { line in
            // Blank lines around it keep it a block of its own.
            parse(line).map { "\n" + html(link: $0.link, label: $0.label) + "\n" }
        }
    }

    /// True when the Markdown has a Buy button line outside code blocks.
    static func isUsed(in markdown: String) -> Bool {
        var found = false
        PageWidget.eachLine(of: markdown) { line in
            if parse(line) != nil { found = true }
            return nil
        }
        return found
    }

    /// The button: the theme's button style, opening checkout in a new tab.
    static func html(link: String, label: String) -> String {
        #"<p class="buy-button">"# + anchor(link: link, label: label, className: "button buy") + "</p>"
    }

    /// A Buy link that opens checkout in a new tab (or window, as the
    /// visitor's browser does it), with the open-in-new-window icon after
    /// the text. Screen readers hear that it opens a new tab.
    static func anchor(link: String, label: String, className: String) -> String {
        let text = escapeHTML(label.trimmingCharacters(in: .whitespaces).isEmpty ? defaultLabel : label)
        return #"<a class="\#(className)" href="\#(escapeHTML(link))" target="_blank" rel="noopener" aria-label="\#(text) (opens in a new tab)">"#
            + text + newWindowIcon + "</a>"
    }

    /// Lucide's external-link icon (ISC), in the button's text color and
    /// the text's size, so it works with any theme.
    static let newWindowIcon = #"<svg class="buy-icon" width="1em" height="1em" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" style="display:inline-block;vertical-align:-0.125em;margin-left:0.4em">"#
        + (NavIcon.named("external-link")?.inner ?? "") + "</svg>"
}
