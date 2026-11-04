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
        try "---\ntype: product\ntitle: Clicker Keychain\nprice: $5.48\ndiscount: 30\ncover: /media/files/clicker.jpg\n---\nHi"
            .write(to: pages.appending(path: "clicker.md"), atomically: true, encoding: .utf8)
        try "---\ntype: product\ntitle: Sticker\nprice: $3.00\n---\nHi"
            .write(to: pages.appending(path: "sticker.md"), atomically: true, encoding: .utf8)
        site = try Site.load(from: root)
        let renderer = try SiteRenderer(site: site)
        let list = try #require(renderer.render(path: shop.mainPath))
        #expect(list.contains(#"<div class="collection-grid product-grid" style="--cols:4">"#))
        #expect(list.contains(#"<a class="product-tile" href="/shop/pages/clicker/"><span class="product-image"><img src="/media/files/clicker.jpg" alt="" loading="lazy"></span><h2 title="Clicker Keychain">Clicker Keychain</h2><p class="price on-sale"><span class="price-now">$3.84</span>"#))
        #expect(list.contains(#"<h2 title="Sticker">Sticker</h2><p class="price">$3.00</p></a>"#))
        #expect(list.contains(".product-image { display: block; aspect-ratio: 4 / 5;"))

        // The product page shows the sale too, with its styles.
        let page = try #require(renderer.render(path: "/shop/pages/clicker/"))
        #expect(page.contains(#"<s class="price-was">$5.48</s> <span class="price-off">(30% off)</span>"#))
        #expect(page.contains(".price.on-sale .price-was"))
    }
}
