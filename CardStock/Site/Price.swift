import Foundation

/// Sale prices for products: a price as typed ("$24.00", "5,48 €",
/// "1,200 USD") with a percentage off, giving the sale price in the same
/// format. Prices stay free text; only the first number in them is used.
enum Price {
    /// What a product sells for.
    struct Sale: Equatable, Sendable {
        /// The price after the discount, e.g. "$3.84".
        var now: String
        /// The price as typed, e.g. "$5.48".
        var was: String
        /// Percent off, 1–99.
        var percent: Int
    }

    /// The discount in `discount` front matter ("30", "30%"), when it's 1–99.
    static func percent(_ text: String?) -> Int? {
        guard var text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if text.hasSuffix("%") { text.removeLast() }
        guard let value = Double(text.trimmingCharacters(in: .whitespaces)) else { return nil }
        let percent = Int(value.rounded())
        return (1...99).contains(percent) ? percent : nil
    }

    /// The sale for a price and a discount, or nil when either is missing
    /// or the price has no number in it.
    static func sale(_ price: String, discount: String?) -> Sale? {
        let price = price.trimmingCharacters(in: .whitespaces)
        guard let percent = percent(discount), let parts = Parts(price) else { return nil }
        let now = parts.value * Decimal(100 - percent) / 100
        return Sale(now: parts.replacingValue(with: now), was: price, percent: percent)
    }

    /// A price split around its number, with how the number is written.
    struct Parts {
        var prefix: Substring
        var suffix: Substring
        var value: Decimal
        /// Digits after the decimal mark (0 when there's none).
        var decimals: Int
        var decimalMark: Character
        /// The thousands separator, when the number uses one.
        var grouping: Character?

        init?(_ text: String) {
            guard let start = text.firstIndex(where: \.isNumber) else { return nil }
            var end = start
            while end < text.endIndex, text[end].isNumber || text[end] == "." || text[end] == "," {
                end = text.index(after: end)
            }
            var number = text[start..<end]
            // A trailing mark is punctuation ("$5." or "5, plus tax"), not part of the number.
            while let last = number.last, !last.isNumber { number.removeLast(); end = text.index(before: end) }
            prefix = text[..<start]
            suffix = text[end...]

            let dots = number.filter { $0 == "." }.count
            let commas = number.filter { $0 == "," }.count
            // Which mark is the decimal one: the last of two kinds, else a
            // single mark followed by one or two digits (5,48 or 5.5).
            var mark: Character?
            if dots > 0 && commas > 0 {
                mark = number.lastIndex(of: ".")! > number.lastIndex(of: ",")! ? "." : ","
            } else if let only: Character = dots > 0 ? "." : commas > 0 ? "," : nil,
                      (only == "." ? dots : commas) == 1 {
                let after = number.distance(from: number.lastIndex(of: only)!, to: number.endIndex) - 1
                mark = after == 3 ? nil : only
            }
            if let mark {
                let other: Character = mark == "." ? "," : "."
                grouping = number.contains(other) ? other : nil
                decimals = number.distance(from: number.lastIndex(of: mark)!, to: number.endIndex) - 1
            } else {
                // No decimal mark: any marks group thousands (1,200 or 1.200).
                grouping = dots > 0 ? "." : commas > 0 ? "," : nil
                decimals = 0
            }
            // Cents added to a whole price use the mark that isn't grouping.
            decimalMark = mark ?? (grouping == "." ? "," : ".")
            let separator = grouping
            var plain = String(number.filter { $0 != separator })
            if let mark, mark == "," { plain = plain.replacingOccurrences(of: ",", with: ".") }
            guard let value = Decimal(string: plain, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
            self.value = value
        }

        /// The price with `value` in place of its number, written the same
        /// way. Whole prices stay whole unless the sale price has cents.
        func replacingValue(with value: Decimal) -> String {
            var rounded = Decimal()
            var exact = value
            let places = decimals > 0 ? decimals : 2
            NSDecimalRound(&rounded, &exact, places, .plain)
            let isWhole = rounded == rounded.rounded(0)
            let shownPlaces = decimals > 0 ? decimals : (isWhole ? 0 : 2)

            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = shownPlaces
            formatter.maximumFractionDigits = shownPlaces
            formatter.usesGroupingSeparator = grouping != nil
            formatter.groupingSize = 3
            formatter.groupingSeparator = grouping.map(String.init) ?? ""
            formatter.decimalSeparator = String(decimalMark)
            let number = formatter.string(from: rounded as NSDecimalNumber) ?? "\(rounded)"
            return String(prefix) + number + String(suffix)
        }
    }

    /// The price as HTML for lists and product pages: just the price, or
    /// the sale price, the old one struck through and the percent off.
    static func html(_ price: String, discount: String?) -> String {
        let price = price.trimmingCharacters(in: .whitespaces)
        guard !price.isEmpty else { return "" }
        guard let sale = sale(price, discount: discount) else {
            return #"<p class="price">\#(escapeHTML(price))</p>"#
        }
        return #"<p class="price on-sale"><span class="price-now">\#(escapeHTML(sale.now))</span> "#
            + #"<s class="price-was">\#(escapeHTML(sale.was))</s> "#
            + #"<span class="price-off">(\#(sale.percent)% off)</span></p>"#
    }
}

private extension Decimal {
    func rounded(_ places: Int) -> Decimal {
        var value = self, result = Decimal()
        NSDecimalRound(&result, &value, places, .plain)
        return result
    }
}
