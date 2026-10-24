import Foundation
import Testing
@testable import CardStock

struct InsightsTests {
    let dir = FileManager.default.temporaryDirectory.appending(path: "cardstock-insights-\(UUID().uuidString)")

    private func site(_ posts: [(slug: String, text: String)] = [], pages: [(String, String)] = []) throws -> Site {
        let root = dir.appending(path: "Site")
        try StarterSite.create(at: root, title: "Site")
        for (slug, text) in posts {
            try SiteMigration.setType("post", in: text)
                .write(to: root.appending(path: "pages/\(slug).md"), atomically: true, encoding: .utf8)
        }
        for (slug, text) in pages {
            try text.write(to: root.appending(path: "pages/\(slug).md"), atomically: true, encoding: .utf8)
        }
        return try Site.load(from: root)
    }

    @Test func countsWords() {
        #expect(SiteInsights.wordCount("Hello **big** world. ![A photo](/media/a.jpg) See [my page](/pages/about/).") == 6)
        #expect(SiteInsights.wordCount("") == 0)
    }

    @Test func writingStats() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = try site([
            ("a", "---\ntitle: A\ndate: 2026-09-01\ntags: [travel, food]\n---\none two three"),
            ("b", "---\ntitle: B\ndate: 2026-10-02\ntags: [travel]\n---\nfour five"),
            ("c", "---\ntitle: C\ndate: 2026-08-15\ndraft: true\n---\ndraft words"),
        ])
        let stats = SiteInsights.writingStats(s)
        // The starter site has its own published post too.
        #expect(stats.drafts >= 1)
        #expect(stats.oldestDraft?.slug == "c")
        #expect(stats.topTags.first?.tag == "travel")
        #expect(stats.topTags.first?.count == 2)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = SiteInsights.isoDate.date(from: "2026-10-21")!
        let months = SiteInsights.postsPerMonth(s, months: 3, now: now, calendar: calendar)
        #expect(months.count == 3)
        #expect(months.last?.count ?? 0 >= 1)   // October has post B
        #expect(months[1].count >= 1)           // September has post A
    }

    @Test func weekStreak() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = SiteInsights.isoDate.date(from: "2026-10-21")!
        let day = { (offset: Int) in calendar.date(byAdding: .day, value: -offset, to: now)! }
        #expect(SiteInsights.weekStreak([day(0), day(7), day(14)], now: now, calendar: calendar) == 3)
        #expect(SiteInsights.weekStreak([day(7), day(14)], now: now, calendar: calendar) == 2)
        #expect(SiteInsights.weekStreak([day(21)], now: now, calendar: calendar) == 0)
    }

    @Test func healthChecks() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = try site([
            ("linky", "---\ntitle: Linky\ndate: 2026-10-01\n---\nSee [about](/pages/about/), [nope](/nope/) and [draft](/blog/pages/secret/). ![](/media/x.jpg)"),
            ("secret", "---\ntitle: Secret\ndate: 2026-10-02\ndraft: true\n---\nhidden"),
        ])
        let checks = SiteInsights.healthChecks(s, files: [], outdatedThemeFiles: [])
        let links = try #require(checks.first { $0.id == "links" })
        #expect(links.problems.count == 2)
        #expect(links.problems.contains { $0.text.contains("/nope/") })
        #expect(links.problems.contains { $0.text.contains("draft") })
        let alt = try #require(checks.first { $0.id == "alt" })
        #expect(alt.problems.count == 1)
        let summary = try #require(checks.first { $0.id == "summary" })
        #expect(summary.problems.contains { $0.text.contains("Linky") })
        #expect(checks.first { $0.id == "theme" }?.passed == true)
    }

    @Test func linkStatus() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = try site()
        #expect(SiteInsights.linkStatus("/", in: s) == .ok)
        #expect(SiteInsights.linkStatus("/pages/about", in: s) == .ok)
        #expect(SiteInsights.linkStatus("/pages/about/#team", in: s) == .ok)
        #expect(SiteInsights.linkStatus("/feed.xml", in: s) == .ok)
        #expect(SiteInsights.linkStatus("/missing/", in: s) == .missing)
    }
}
