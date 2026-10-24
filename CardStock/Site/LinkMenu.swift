import Foundation

/// A link menu is a page of links (`type: links` in its front matter) that
/// isn't published on its own. The footer shows it as a drop-down menu.
enum LinkMenu {
    struct Link: Equatable, Sendable {
        var title: String
        var url: String

        /// True for links to other sites, which open in a new tab.
        var isExternal: Bool { url.contains("://") || url.hasPrefix("mailto:") }
    }

    /// Text for a new link menu page.
    static let starterBody = """
    [YouTube](https://www.youtube.com/)
    [LinkedIn](https://www.linkedin.com/)
    """

    /// The links in a page's Markdown, in order: `[Title](url)` links, plus
    /// bare web addresses, which are named after their site.
    static func links(in markdown: String) -> [Link] {
        let ns = markdown as NSString
        let all = NSRange(location: 0, length: ns.length)
        var found: [(location: Int, link: Link)] = []
        var taken: [NSRange] = []

        let markdownLink = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)"#)
        for match in markdownLink.matches(in: markdown, range: all) {
            let title = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let url = ns.substring(with: match.range(at: 2))
            found.append((match.range.location, Link(title: title, url: url)))
            taken.append(match.range)
        }

        let bare = try! NSRegularExpression(pattern: #"(?:https?://|mailto:)[^\s<>()\[\]"']+"#)
        for match in bare.matches(in: markdown, range: all)
        where !taken.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
            var url = ns.substring(with: match.range)
            while let last = url.last, ".,;:!?".contains(last) { url.removeLast() }
            found.append((match.range.location, Link(title: name(for: url), url: url)))
        }

        return found.sorted { $0.location < $1.location }.map(\.link)
    }

    /// A readable name for a bare address: "YouTube" for youtube.com,
    /// otherwise the site's domain.
    static func name(for url: String) -> String {
        if url.hasPrefix("mailto:") { return String(url.dropFirst("mailto:".count)) }
        guard var host = URL(string: url)?.host()?.lowercased() else { return url }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        if host.hasPrefix("m.") { host.removeFirst(2) }
        let known: [String: String] = [
            "youtube.com": "YouTube", "youtu.be": "YouTube", "linkedin.com": "LinkedIn",
            "instagram.com": "Instagram", "facebook.com": "Facebook", "x.com": "X",
            "twitter.com": "X", "github.com": "GitHub", "tiktok.com": "TikTok",
            "threads.net": "Threads", "threads.com": "Threads", "bsky.app": "Bluesky",
            "pinterest.com": "Pinterest", "vimeo.com": "Vimeo", "behance.net": "Behance",
            "dribbble.com": "Dribbble", "substack.com": "Substack", "medium.com": "Medium",
            "twitch.tv": "Twitch", "reddit.com": "Reddit", "flickr.com": "Flickr",
            "soundcloud.com": "SoundCloud", "spotify.com": "Spotify", "open.spotify.com": "Spotify",
            "etsy.com": "Etsy", "patreon.com": "Patreon", "discord.gg": "Discord",
            "discord.com": "Discord", "mastodon.social": "Mastodon",
        ]
        if let name = known[host] { return name }
        // Subdomains such as you.substack.com.
        if let match = known.first(where: { host.hasSuffix("." + $0.key) }) { return match.value }
        return host
    }
}
