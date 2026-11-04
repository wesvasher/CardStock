import Foundation
import Testing
@testable import CardStock

struct PriceTests {
    @Test func salePricesKeepTheFormat() {
        #expect(Price.sale("$5.48", discount: "30") == .init(now: "$3.84", was: "$5.48", percent: 30))
        #expect(Price.sale("$29.98", discount: "50%")?.now == "$14.99")
        #expect(Price.sale("$12.00", discount: "20")?.now == "$9.60")
        // Whole prices stay whole unless the sale has cents.
        #expect(Price.sale("$20", discount: "25")?.now == "$15")
        #expect(Price.sale("$15", discount: "15")?.now == "$12.75")
        // Thousands, decimal commas and currency after the number.
        #expect(Price.sale("$1,200.00", discount: "10")?.now == "$1,080.00")
        #expect(Price.sale("1,200 USD", discount: "10")?.now == "1,080 USD")
        #expect(Price.sale("5,48 €", discount: "30")?.now == "3,84 €")
        #expect(Price.sale("1.299,00 €", discount: "10")?.now == "1.169,10 €")
        #expect(Price.sale("£40 each", discount: "10")?.now == "£36 each")
    }

    @Test func discountsMustMakeSense() {
        #expect(Price.percent("30") == 30)
        #expect(Price.percent(" 12.5 % ") == 13)
        #expect(Price.percent("0") == nil)
        #expect(Price.percent("100") == nil)
        #expect(Price.percent("half") == nil)
        #expect(Price.percent(nil) == nil)
        #expect(Price.sale("Free", discount: "30") == nil)
        #expect(Price.sale("$10", discount: "") == nil)
    }

    @Test func priceHTML() {
        #expect(Price.html("$10", discount: nil) == #"<p class="price">$10</p>"#)
        #expect(Price.html("$5.48", discount: "30")
                == #"<p class="price on-sale"><span class="price-now">$3.84</span> <s class="price-was">$5.48</s> <span class="price-off">(30% off)</span></p>"#)
        #expect(Price.html("", discount: "30").isEmpty)
    }

    /// Hover videos: on the tile over the photo, loading only on hover,
    /// with the script added only to pages that have them.
    @Test func hoverVideos() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "cardstock-hover-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = dir.appending(path: "Site")
        try StarterSite.create(at: root, title: "Site")
        var site = try Site.load(from: root)
        let shop = ContentCollection(preset: .shop, id: ContentCollection.shopID)
        site.config.collections = site.config.collections.filter { $0.id != shop.id } + [shop]
        try site.saveConfig()
        let pages = root.appending(path: "pages")
        try "---\ntype: product\ntitle: Mug\nprice: $10\ncover: /media/files/mug.jpg\nhoverVideo: media/files/mug.mp4\n---\n"
            .write(to: pages.appending(path: "mug.md"), atomically: true, encoding: .utf8)
        try "---\ntype: product\ntitle: Clip Only\nprice: $5\nhoverVideo: /media/files/clip.webm\n---\n"
            .write(to: pages.appending(path: "clip.md"), atomically: true, encoding: .utf8)
        try "---\ntype: product\ntitle: Linked\nprice: $5\nhoverVideo: https://youtu.be/abc\n---\n"
            .write(to: pages.appending(path: "linked.md"), atomically: true, encoding: .utf8)
        site = try Site.load(from: root)
        let html = try #require(try SiteRenderer(site: site).render(path: shop.mainPath))
        #expect(html.contains(#"<div class="product-tile has-video"><a class="product-link" href="/shop/pages/mug/"><span class="product-image"><img src="/media/files/mug.jpg" alt="" loading="lazy"><video class="product-hover-video" src="/media/files/mug.mp4" muted loop playsinline preload="none" aria-hidden="true" tabindex="-1"></video><span class="product-video-badge""#))
        // No photo: the video's first frame stands in.
        #expect(html.contains(#"<video class="product-hover-video is-still" src="/media/files/clip.webm#t=0.1" muted loop playsinline preload="metadata""#))
        // Links aren't video files.
        #expect(html.contains(#"<div class="product-tile"><a class="product-link" href="/shop/pages/linked/">"#))
        #expect(html.contains(#"tile.addEventListener("focusin", play);"#))
        #expect(html.contains(#"window.matchMedia("(hover: hover)")"#))

        // Pages without hover videos don't get the script.
        let about = try #require(try SiteRenderer(site: site).render(path: "/pages/about/"))
        #expect(!about.contains("(hover: hover)"))

        #expect(SiteRenderer.isVideoFile("/media/files/a.MOV"))
        #expect(SiteRenderer.isVideoFile("clip.mp4?v=2"))
        #expect(!SiteRenderer.isVideoFile("/media/files.mp4/readme"))
        #expect(!SiteRenderer.isVideoFile("https://vimeo.com/123"))
    }

    @Test func previewByteRanges() {
        #expect(PreviewSchemeHandler.byteRange("bytes=0-1", length: 100) == 0..<2)
        #expect(PreviewSchemeHandler.byteRange("bytes=10-", length: 100) == 10..<100)
        #expect(PreviewSchemeHandler.byteRange("bytes=-20", length: 100) == 80..<100)
        #expect(PreviewSchemeHandler.byteRange("bytes=50-999", length: 100) == 50..<100)
        #expect(PreviewSchemeHandler.byteRange("bytes=100-", length: 100) == nil)
        #expect(PreviewSchemeHandler.byteRange("bytes=0-1,5-6", length: 100) == nil)
        #expect(PreviewSchemeHandler.byteRange("items=0-1", length: 100) == nil)
    }

    /// The Store list: tiles with the photo, name and sale price.
    @Test func storeTiles() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "cardstock-price-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = dir.appending(path: "Site")
        try StarterSite.create(at: root, title: "Site")
        var site = try Site.load(from: root)
        let shop = ContentCollection(preset: .shop, id: ContentCollection.shopID)
        #expect(shop.listStyle == .products && shop.columns == 4)
        site.config.collections = site.config.collections.filter { $0.id != shop.id } + [shop]
        try site.saveConfig()
        let pages = root.appending(path: "pages")
        try "---\ntype: product\ntitle: Clicker Keychain\nprice: $5.48\ndiscount: 30\ncover: /media/files/clicker.jpg\nbuy: https://buy.stripe.com/test_123\nbuyLabel: Pay Now\n---\nHi"
            .write(to: pages.appending(path: "clicker.md"), atomically: true, encoding: .utf8)
        try "---\ntype: product\ntitle: Sticker\nprice: $3.00\n---\nHi"
            .write(to: pages.appending(path: "sticker.md"), atomically: true, encoding: .utf8)
        site = try Site.load(from: root)
        let renderer = try SiteRenderer(site: site)
        let list = try #require(renderer.render(path: shop.mainPath))
        #expect(list.contains(#"<div class="collection-grid product-grid" style="--cols:4">"#))
        #expect(list.contains(#"<div class="product-tile"><a class="product-link" href="/shop/pages/clicker/"><span class="product-image"><img src="/media/files/clicker.jpg" alt="" loading="lazy"></span><h2 title="Clicker Keychain">Clicker Keychain</h2><p class="price on-sale"><span class="price-now">$3.84</span>"#))
        #expect(list.contains(#"<h2 title="Sticker">Sticker</h2><p class="price">$3.00</p></a>"#))
        // Under the price: the outlined button to the page, and the Buy link when there is one.
        #expect(list.contains(#"<div class="product-actions"><a class="product-button" href="/shop/pages/clicker/" aria-label="View Details: Clicker Keychain">View Details</a><a class="product-pay" href="https://buy.stripe.com/test_123" target="_blank" rel="noopener" aria-label="Pay Now: Clicker Keychain">Pay Now <span aria-hidden="true">&rarr;</span></a></div></div>"#))
        #expect(list.contains(#"<a class="product-button" href="/shop/pages/sticker/" aria-label="View Details: Sticker">View Details</a></div></div>"#))
        #expect(list.contains(".product-image { position: relative; display: block; aspect-ratio: 4 / 5;"))

        // The button's text is a collection setting, and the buttons can be turned off.
        site.config.collections[site.config.collections.count - 1].tileButtonText = "See It"
        #expect(try SiteRenderer(site: site).render(path: shop.mainPath)?.contains(">See It</a>") == true)
        site.config.collections[site.config.collections.count - 1].tileButtons = false
        #expect(try SiteRenderer(site: site).render(path: shop.mainPath)?.contains(#"class="product-actions""#) == false)

        // The product page shows the sale too, with its styles.
        let page = try #require(renderer.render(path: "/shop/pages/clicker/"))
        #expect(page.contains(#"<s class="price-was">$5.48</s> <span class="price-off">(30% off)</span>"#))
        #expect(page.contains(".price.on-sale .price-was"))
    }
}
