import Foundation
import Testing
@testable import CardStock

/// Configuration → Shopping and Buy buttons: the `<!-- buy … -->` line,
/// Page Settings' Payment link, and where they're saved.
struct ShoppingTests {
    let dir = FileManager.default.temporaryDirectory.appending(path: "cardstock-shopping-\(UUID().uuidString)")

    @Test func buttonLines() {
        let line = BuyButton.marker(link: "https://buy.stripe.com/abc123", label: "Buy the print")
        #expect(line == #"<!-- buy https://buy.stripe.com/abc123 "Buy the print" -->"#)
        let parsed = BuyButton.parse(line)
        #expect(parsed?.link == "https://buy.stripe.com/abc123" && parsed?.label == "Buy the print")
        // No text: Buy Now. Case and spacing don't matter.
        #expect(BuyButton.parse("  <!--BUY https://buy.stripe.com/x-->")?.label == "Buy Now")
        // Not links, or not buy lines.
        #expect(BuyButton.parse("<!-- buy now -->") == nil)
        #expect(BuyButton.parse("<!-- buy javascript:alert(1) -->") == nil)
        #expect(BuyButton.parse("<!-- newsletter -->") == nil)
        // Quotes and -- can't end the line early.
        #expect(BuyButton.marker(link: "https://buy.stripe.com/x", label: #"The "Big" one -- now"#)
            == #"<!-- buy https://buy.stripe.com/x "The ”Big” one – now" -->"#)
    }

    @Test func stripeLinks() {
        #expect(BuyButton.isStripeLink("https://buy.stripe.com/test_abc"))
        #expect(!BuyButton.isStripeLink("https://example.com/buy"))
        #expect(BuyButton.isWebLink("https://example.com/buy"))
        #expect(!BuyButton.isWebLink("buy.stripe.com/abc"))
    }

    @Test func buttonsInMarkdown() {
        let markdown = """
        Prints for sale.

        <!-- buy https://buy.stripe.com/abc "Buy <now>" -->

        ```
        <!-- buy https://buy.stripe.com/code -->
        ```
        """
        #expect(BuyButton.isUsed(in: markdown))
        let html = SiteRenderer.markdownToHTML(markdown)
        #expect(html.contains(#"<a class="button buy" href="https://buy.stripe.com/abc" target="_blank" rel="noopener" aria-label="Buy &lt;now&gt; (opens in a new tab)">Buy &lt;now&gt;<svg class="buy-icon""#))
        #expect(BuyButton.newWindowIcon.contains("M15 3h6v6"))
        // Lines in code blocks stay as text.
        #expect(!html.contains(#"href="https://buy.stripe.com/code""#))
        #expect(!BuyButton.isUsed(in: "```\n<!-- buy https://buy.stripe.com/code -->\n```"))
    }

    @Test func savedInSiteJSON() throws {
        var config = SiteConfig()
        #expect(config.shopping.provider == .none)
        config.shopping.provider = .stripePaymentLinks
        config.shopping.buttonLabel = "Get it"
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(SiteConfig.self, from: data)
        #expect(decoded.shopping.usesPaymentLinks && decoded.shopping.buttonLabel == "Get it")
        // A service from a newer CardStock reads as none.
        let newer = try JSONDecoder().decode(SiteConfig.self, from: Data(#"{"shopping": {"provider": "snipcart"}}"#.utf8))
        #expect(newer.shopping.provider == .none)
        #expect(SiteConfig.Shopping().shownButtonLabel == "Buy Now")
    }

    @Test func paymentLinkInPageSettings() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = dir.appending(path: "Site")
        try StarterSite.create(at: root, title: "Site")
        try "---\ntitle: Print\nbuy: https://buy.stripe.com/print\n---\nA print.".write(
            to: root.appending(path: "pages/print.md"), atomically: true, encoding: .utf8)
        var site = try Site.load(from: root)

        // Off: no button from Page Settings.
        var html = try #require(try SiteRenderer(site: site).render(path: "/pages/print/"))
        #expect(!html.contains("buy.stripe.com/print"))

        site.config.shopping.provider = .stripePaymentLinks
        site.config.shopping.buttonLabel = "Get a print"
        html = try #require(try SiteRenderer(site: site).render(path: "/pages/print/"))
        #expect(html.contains(#"href="https://buy.stripe.com/print""#) && html.contains("Get a print"))

        // The preview's sample page.
        let sample = try #require(try SiteRenderer(site: site, includeDrafts: true).render(path: SiteRenderer.shoppingPreviewPath))
        #expect(sample.contains(#"class="button buy""#))
        #expect(!(try SiteRenderer(site: site).paths.contains(SiteRenderer.shoppingPreviewPath)))
    }
}
