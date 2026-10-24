import Foundation

/// Numbers and checks about a site for the Start page dashboard: writing
/// stats, publishing activity, and a health checklist. No UI here.
enum SiteInsights {
    static let wordsPerMinute = 220

    // MARK: - Writing

    struct WritingStats: Equatable {
        var publishedPosts = 0
        var drafts = 0
        /// The draft that has waited longest (by its date).
        var oldestDraft: ContentItem?
        var totalWords = 0
        /// Average minutes to read a published post.
        var averageReadingMinutes = 0
        var topTags: [(tag: String, count: Int)] = []

        static func == (a: WritingStats, b: WritingStats) -> Bool {
            a.publishedPosts == b.publishedPosts && a.drafts == b.drafts && a.oldestDraft?.id == b.oldestDraft?.id
                && a.totalWords == b.totalWords && a.averageReadingMinutes == b.averageReadingMinutes
                && a.topTags.map(\.tag) == b.topTags.map(\.tag) && a.topTags.map(\.count) == b.topTags.map(\.count)
        }
    }

    static func writingStats(_ site: Site, tagLimit: Int = 6) -> WritingStats {
        let posts = site.items(.post)
        let published = posts.filter { !$0.isDraft }
        let drafts = posts.filter(\.isDraft)
        var stats = WritingStats()
        stats.publishedPosts = published.count
        stats.drafts = drafts.count
        stats.oldestDraft = drafts.min { ($0.date.isEmpty ? "9999" : $0.date) < ($1.date.isEmpty ? "9999" : $1.date) }
        stats.totalWords = published.reduce(0) { $0 + wordCount($1.body) }
        if !published.isEmpty {
            let minutes = Double(stats.totalWords) / Double(wordsPerMinute) / Double(published.count)
            stats.averageReadingMinutes = max(1, Int(minutes.rounded()))
        }
        var tags: [String: Int] = [:]
        for post in published {
            for tag in post.frontMatter.list("tags") { tags[tag, default: 0] += 1 }
        }
        stats.topTags = tags.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(tagLimit).map { ($0.key, $0.value) }
        return stats
    }

    /// Words in Markdown, not counting image and link addresses or symbols.
    static func wordCount(_ markdown: String) -> Int {
        var text = markdown
        // Drop image markup entirely and keep only link text.
        text = text.replacingOccurrences(of: #"!\[[^\]]*\]\([^)]*\)"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        return text.split { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "’" }.count
    }

    /// Published posts per month for the last `months` months, oldest first.
    static func postsPerMonth(_ site: Site, months: Int = 12, now: Date = .now,
                              calendar: Calendar = .current) -> [(month: Date, count: Int)] {
        guard let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else { return [] }
        let starts = (0..<months).reversed().compactMap { calendar.date(byAdding: .month, value: -$0, to: thisMonth) }
        var counts = Dictionary(uniqueKeysWithValues: starts.map { ($0, 0) })
        for post in site.items(.post) where !post.isDraft {
            guard let date = isoDate.date(from: post.date),
                  let month = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
                  counts[month] != nil else { continue }
            counts[month]! += 1
        }
        return starts.map { ($0, counts[$0] ?? 0) }
    }

    static let isoDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Activity

    /// How many things happened on each day, keyed by the start of the day.
    static func dailyCounts(_ dates: [Date], calendar: Calendar = .current) -> [Date: Int] {
        var counts: [Date: Int] = [:]
        for date in dates { counts[calendar.startOfDay(for: date), default: 0] += 1 }
        return counts
    }

    /// Weeks in a row, ending this week (or last week), with at least one date.
    static func weekStreak(_ dates: [Date], now: Date = .now, calendar: Calendar = .current) -> Int {
        func weekStart(_ d: Date) -> Date? { calendar.dateInterval(of: .weekOfYear, for: d)?.start }
        let weeks = Set(dates.compactMap(weekStart))
        guard var week = weekStart(now) else { return 0 }
        // A quiet week so far doesn't break the streak yet.
        if !weeks.contains(week) { week = calendar.date(byAdding: .weekOfYear, value: -1, to: week) ?? week }
        var streak = 0
        while weeks.contains(week) {
            streak += 1
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: week) else { break }
            week = previous
        }
        return streak
    }

    /// Dates of published posts, for sites without git history.
    static func postDates(_ site: Site) -> [Date] {
        site.items(.post).filter { !$0.isDraft }.compactMap { isoDate.date(from: $0.date) }
    }

    // MARK: - Health

    struct Problem: Identifiable, Equatable {
        var text: String
        var action: Action
        var id: String { text }
    }

    enum Action: Equatable {
        case openItem(URL)
        case siteDetails
        case menu
        case footer
        case newsletter
        case files
        case theming
    }

    struct Check: Identifiable, Equatable {
        enum Severity: Equatable { case warning, critical }
        var id: String
        var title: String
        /// Shown when there's nothing to fix.
        var passText: String
        var severity: Severity
        var problems: [Problem]
        var passed: Bool { problems.isEmpty }
    }

    /// Runs every check. `files` and `outdatedThemeFiles` come from the app,
    /// which keeps them up to date.
    static func healthChecks(_ site: Site, files: [MediaFile], outdatedThemeFiles: [String]) -> [Check] {
        var checks: [Check] = []

        // Links that lead nowhere on the live site.
        var broken: [Problem] = []
        for item in site.items where !item.isDraft {
            for link in internalLinks(in: item.body) {
                switch linkStatus(link, in: site) {
                case .ok: continue
                case .draft: broken.append(Problem(text: "“\(item.title)” links to a draft: \(link)", action: .openItem(item.id)))
                case .missing: broken.append(Problem(text: "“\(item.title)” links to \(link), which doesn't exist", action: .openItem(item.id)))
                }
            }
        }
        let configLinks = site.config.menuLinks.map { ($0.url, "Menu", Action.menu) }
            + site.config.footer.links.map { ($0.url, "Footer", Action.footer) }
        for (link, place, action) in configLinks {
            guard link.hasPrefix("/") && !link.hasPrefix("//") else { continue }
            if linkStatus(link, in: site) != .ok {
                broken.append(Problem(text: "\(place) link to \(link) doesn't lead to a published page", action: action))
            }
        }
        checks.append(Check(id: "links", title: "Broken links", passText: "Every link to your own pages works.",
                            severity: .critical, problems: broken))

        // Images without a description.
        var undescribed: [Problem] = []
        for item in site.items where !item.isDraft {
            let count = imagesWithoutDescription(in: item.body)
            if count > 0 {
                undescribed.append(Problem(text: "“\(item.title)” has \(count) \(count == 1 ? "image" : "images") without a description",
                                           action: .openItem(item.id)))
            }
        }
        checks.append(Check(id: "alt", title: "Image descriptions", passText: "Every image has a description.",
                            severity: .warning, problems: undescribed))

        // Posts without a summary look bare in lists and when shared.
        let noSummary = site.items(.post).filter { !$0.isDraft && ($0.frontMatter.string("summary") ?? "").isEmpty }
        checks.append(Check(id: "summary", title: "Post summaries", passText: "Every published post has a summary.",
                            severity: .warning,
                            problems: noSummary.map { Problem(text: "“\($0.title)” has no summary", action: .openItem($0.id)) }))

        // Files too big for Cloudflare.
        let tooBig = files.filter { file in
            file.allPaths.contains { path in
                let size = (try? site.root.appending(path: path).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return Int64(size) > SiteStorage.cloudflareMaxFileBytes
            }
        }
        checks.append(Check(id: "size", title: "File sizes", passText: "No file is too big for Cloudflare (25 MB).",
                            severity: .critical,
                            problems: tooBig.map { Problem(text: "\($0.name) is over 25 MB, so Cloudflare won't serve it", action: .files) }))

        // Unused files are still published.
        let unused = files.filter(\.usedIn.isEmpty)
        checks.append(Check(id: "unused", title: "Unused files", passText: "Every file is used on a page.",
                            severity: .warning,
                            problems: unused.isEmpty ? [] : [Problem(
                                text: "\(unused.count) \(unused.count == 1 ? "file isn't" : "files aren't") used on any page but still \(unused.count == 1 ? "gets" : "get") published",
                                action: .files)]))

        // Pages set to a layout that isn't in theme/layouts.
        let layoutIDs = Set(site.layouts.map(\.id))
        let missingLayouts = site.items.filter { !$0.layout.isEmpty && !layoutIDs.contains($0.layout) }
        checks.append(Check(id: "layouts", title: "Layouts", passText: "Every page's layout is there.",
                            severity: .warning,
                            problems: missingLayouts.map {
                                Problem(text: "“\($0.title)” uses the “\($0.layout)” layout, which isn't in theme/layouts, so it shows in Standard",
                                        action: .openItem($0.id))
                            }))

        // Pages with a newsletter box but no sign-up form to show in it.
        let newsletterPages = site.config.newsletter.hasEmbed ? []
            : site.items.filter { !$0.isLinkMenu && SiteConfig.Newsletter.isUsed(in: $0.body) }
        checks.append(Check(id: "newsletter", title: "Mailing list", passText: "Mailing list boxes have a sign-up form.",
                            severity: .warning,
                            problems: newsletterPages.isEmpty ? [] : [Problem(
                                text: newsletterPages.count == 1
                                    ? "“\(newsletterPages[0].title)” has a mailing list sign-up box, but there's no embed code yet, so it doesn't show"
                                    : "\(newsletterPages.count) pages have a mailing list sign-up box, but there's no embed code yet, so it doesn't show",
                                action: .newsletter)]))

        // Theme files from before newer features.
        checks.append(Check(id: "theme", title: "Theme files", passText: "Your theme files are up to date.",
                            severity: .warning,
                            problems: outdatedThemeFiles.isEmpty ? [] : [Problem(
                                text: "Some theme files are out of date, so newer features won't show",
                                action: .theming)]))
        return checks
    }

    enum LinkStatus: Equatable { case ok, draft, missing }

    /// Where a site address leads.
    static func linkStatus(_ link: String, in site: Site) -> LinkStatus {
        var path = link
        if let cut = path.firstIndex(where: { $0 == "?" || $0 == "#" }) { path = String(path[..<cut]) }
        path = path.removingPercentEncoding ?? path
        if path.isEmpty || ["/", "/index.html", "/shop/", "/shop/index.html", "/feed.xml", "/404.html"].contains(path) {
            return .ok
        }
        let fm = FileManager.default
        if path.hasPrefix("/media/") {
            return fm.fileExists(atPath: site.root.appending(path: String(path.dropFirst())).path) ? .ok : .missing
        }
        if path.hasPrefix("/assets/") {
            return fm.fileExists(atPath: site.root.appending(path: "theme" + path).path) ? .ok : .missing
        }
        if fm.fileExists(atPath: site.root.appending(path: "static" + path).path) { return .ok }
        var page = path.hasSuffix("/index.html") ? String(path.dropLast("index.html".count)) : path
        if !page.hasSuffix("/") && !page.contains(".") { page += "/" }
        if let item = site.items.first(where: { $0.path == page }) {
            return item.isDraft ? .draft : .ok
        }
        return .missing
    }

    /// Addresses on this site linked from Markdown or HTML, such as `/about/`.
    static func internalLinks(in markdown: String) -> [String] {
        let patterns = [#"(?<!!)\[[^\]]*\]\((/[^)\s]*)"#, #"href="(/[^"]*)""#]
        var links: [String] = []
        let ns = markdown as NSString
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: markdown, range: NSRange(location: 0, length: ns.length)) {
                let link = ns.substring(with: match.range(at: 1))
                if !link.hasPrefix("//") { links.append(link) }
            }
        }
        return links
    }

    /// Images with an empty description, in Markdown or HTML.
    static func imagesWithoutDescription(in markdown: String) -> Int {
        let ns = markdown as NSString
        let range = NSRange(location: 0, length: ns.length)
        let markdownImages = (try? NSRegularExpression(pattern: #"!\[\s*\]\("#))?.numberOfMatches(in: markdown, range: range) ?? 0
        let htmlImages = (try? NSRegularExpression(pattern: #"<img(?![^>]*\balt="[^"]+")[^>]*>"#, options: .caseInsensitive))?
            .numberOfMatches(in: markdown, range: range) ?? 0
        return markdownImages + htmlImages
    }
}
