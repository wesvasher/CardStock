import Foundation

/// Videos in a page's Markdown. A line with a YouTube or Vimeo player's
/// embed code (`<iframe src="https://www.youtube.com/embed/…">`), or just a
/// link to a video on a line of its own, becomes the same player item pages
/// use (`SiteRenderer.videoEmbedHTML`): full width, 16:9, and YouTube's
/// privacy-enhanced address. Lines in code blocks are left alone.
enum VideoEmbed {
    static func markPlaces(in markdown: String) -> String {
        let lower = markdown.lowercased()
        guard lower.contains("youtu") || lower.contains("vimeo") else { return markdown }
        return PageWidget.eachLine(of: markdown) { line in
            // Blank lines around it keep it a block of its own.
            link(in: line).map { "\n" + SiteRenderer.videoEmbedHTML($0) + "\n" }
        }
    }

    /// The video address in a line that's only an embed or a link, if it's
    /// a YouTube or Vimeo video.
    static func link(in line: String) -> String? {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.lowercased().hasPrefix("<iframe") {
            guard t.lowercased().hasSuffix("</iframe>") || t.hasSuffix("/>"),
                  let regex = try? NSRegularExpression(pattern: #"\ssrc\s*=\s*["']([^"']+)["']"#, options: .caseInsensitive),
                  let match = regex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
                  let range = Range(match.range(at: 1), in: t) else { return nil }
            t = String(t[range]).replacingOccurrences(of: "&amp;", with: "&")
            if t.hasPrefix("//") { t = "https:" + t }
        } else if t.hasPrefix("<") && t.hasSuffix(">") {
            t = String(t.dropFirst().dropLast())
        }
        guard t.lowercased().hasPrefix("http"), !t.contains(where: \.isWhitespace) else { return nil }
        return isVideo(t) ? t : nil
    }

    static func isVideo(_ link: String) -> Bool {
        if SiteRenderer.youTubeID(link) != nil { return true }
        guard let url = URL(string: link), url.host()?.lowercased().hasSuffix("vimeo.com") == true else { return false }
        return url.path().split(separator: "/").contains { $0.allSatisfy(\.isNumber) }
    }

    /// For the preview only: YouTube refuses to play in a page that isn't
    /// served from a web address (Error 153), so each YouTube player becomes
    /// its thumbnail, which opens the video in the browser. Published pages
    /// keep the player.
    static func previewPlaceholders(in html: String) -> String {
        guard html.contains("youtube"),
              let regex = try? NSRegularExpression(
                pattern: #"<iframe\b[^>]*?\ssrc="(?:https?:)?//(?:www\.)?youtube(?:-nocookie)?\.com/embed/([A-Za-z0-9_-]+)[^"]*"[^>]*>\s*</iframe>"#,
                options: .caseInsensitive) else { return html }
        let ns = html as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let id = ns.substring(with: match.range(at: 1))
            let src = ns.substring(with: match.range)
            let start = SiteRenderer.youTubeStart(attribute("src", in: src) ?? "").map { "&t=\($0)s" } ?? ""
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            result += """
            <a href="https://www.youtube.com/watch?v=\(id)\(start)" title="Watch on YouTube" style="display:flex;flex-direction:column;align-items:center;justify-content:center;gap:12px;width:100%;aspect-ratio:16/9;background:#000 url(https://i.ytimg.com/vi/\(id)/hqdefault.jpg) center/cover;text-decoration:none;color:#fff;font:600 13px -apple-system,system-ui,sans-serif"><span style="width:68px;height:48px;border-radius:12px;background:#f00;display:flex;align-items:center;justify-content:center"><span style="border-style:solid;border-width:10px 0 10px 17px;border-color:transparent transparent transparent #fff;margin-left:4px"></span></span><span style="background:rgba(0,0,0,.7);padding:4px 10px;border-radius:6px">YouTube videos play on your published site. Click to watch on YouTube.</span></a>
            """
            last = match.range.location + match.range.length
        }
        guard last > 0 else { return html }
        return result + ns.substring(from: last)
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"\s\#(name)\s*=\s*"([^"]*)""#, options: .caseInsensitive),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
              let range = Range(match.range(at: 1), in: tag) else { return nil }
        return String(tag[range]).replacingOccurrences(of: "&amp;", with: "&")
    }
}
