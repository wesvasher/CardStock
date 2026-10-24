import Foundation

/// Turns a pasted web font link into custom fonts for the Theming panel.
enum WebFontLookup {
    static let fontFileExtensions: Set<String> = ["woff2", "woff", "ttf", "otf"]

    /// Finds the first https URL in pasted text, which may be a bare URL,
    /// a `<link>` tag, or a CSS `@import`.
    static func extractURL(from pasted: String) -> URL? {
        let text = pasted.replacingOccurrences(of: "&amp;", with: "&")
        guard let range = text.range(of: #"https://[^\s"'()<>]+"#, options: .regularExpression) else { return nil }
        return URL(string: String(text[range]))
    }

    /// Google Fonts share and specimen pages (fonts.google.com/share?…,
    /// fonts.google.com/specimen/Name) as the stylesheet link for the same
    /// fonts. Other links come back unchanged.
    static func stylesheetURL(for url: URL) -> URL {
        guard url.host()?.lowercased() == "fonts.google.com" else { return url }
        var families: [String] = []
        if url.path().hasPrefix("/specimen/") {
            families = [url.lastPathComponent]
        } else if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            // selection.family=Open+Sans:ital,wght@0,300..800|Titillium+Web:wght@400
            families = items.filter { $0.name == "selection.family" }
                .flatMap { ($0.value ?? "").split(separator: "|").map(String.init) }
        }
        families = families
            .map { $0.replacingOccurrences(of: " ", with: "+").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !families.isEmpty else { return url }
        let query = families.map { "family=" + $0 }.joined(separator: "&") + "&display=swap"
        return URL(string: "https://fonts.googleapis.com/css2?" + query) ?? url
    }

    /// Unique `font-family` names declared in a stylesheet's `@font-face` rules, in order.
    static func families(inCSS css: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        let pattern = #"font-family\s*:\s*['"]?([^;'"}]+?)['"]?\s*[;}]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = css as NSString
        for match in regex.matches(in: css, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, seen.insert(name.lowercased()).inserted { result.append(name) }
        }
        return result
    }

    /// A readable family name from a font file name: "Recoleta-Bold.woff2" → "Recoleta Bold".
    static func familyName(fromFile url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        let words = base.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        return words.split(separator: " ").joined(separator: " ")
    }

    /// Guesses whether a family is serif, sans or monospace from its name.
    static func guessStyle(_ family: String) -> ThemeSettings.CustomFont.Style {
        let lower = family.lowercased()
        if lower.contains("mono") || lower.contains("code") { return .mono }
        if lower.contains("serif") && !lower.contains("sans") { return .serif }
        return .sans
    }

    /// Resolves a pasted link to one font per family it provides.
    static func lookUp(_ pasted: String) async throws -> [ThemeSettings.CustomFont] {
        guard let pastedURL = extractURL(from: pasted) else {
            throw SiteError("That doesn't look like a web font link. Paste an address starting with https://.")
        }
        let url = stylesheetURL(for: pastedURL)
        if fontFileExtensions.contains(url.pathExtension.lowercased()) {
            let family = familyName(fromFile: url)
            return [.init(family: family, url: url.absoluteString, style: guessStyle(family))]
        }

        var request = URLRequest(url: url)
        // Some font services tailor the CSS to the browser; ask as Safari would.
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw SiteError("Couldn't load that link: \(error.localizedDescription)")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw SiteError("That link returned an error (\(status)). Check that it's copied in full.")
        }
        let text = String(decoding: data, as: UTF8.self)
        // A web page (such as a font's page on a font site) declares the
        // site's own fonts, not the ones wanted.
        let type = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if type.contains("text/html") || text.prefix(200).lowercased().contains("<!doctype html") || text.prefix(200).lowercased().contains("<html") {
            throw SiteError("That link is a web page, not a font stylesheet. On Google Fonts, click “Get embed code” and copy the <link> tag, or paste the font's share link.")
        }
        let families = families(inCSS: text)
        guard !families.isEmpty else {
            throw SiteError("No fonts were found at that link. Paste a font stylesheet link (like one from Google Fonts) or a direct link to a .woff2 file.")
        }
        return families.map { .init(family: $0, url: url.absoluteString, style: guessStyle($0)) }
    }
}
