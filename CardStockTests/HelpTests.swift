import Foundation
import Testing
@testable import CardStock

struct HelpTests {
    @Test func everyArticleLoads() throws {
        let folder = try #require(Bundle.main.url(forResource: "Help", withExtension: nil))
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".md") }
        #expect(HelpCenter.articles.count == files.count)
        for category in HelpCategory.allCases {
            #expect(HelpCenter.articles.contains { $0.category == category }, "\(category) has no articles")
        }
    }

    @Test func linksPointSomewhere() throws {
        let ids = Set(HelpCenter.articles.map(\.id))
        let appTargets = Set(["configuration", "publishing", "files", "pages", "home"] + ConfigPage.allCases.map(\.linkName))
        let regex = try NSRegularExpression(pattern: #"\]\((help|cardstock):([^)]+)\)"#)
        for article in HelpCenter.articles {
            let ns = article.body as NSString
            for match in regex.matches(in: article.body, range: NSRange(location: 0, length: ns.length)) {
                let scheme = ns.substring(with: match.range(at: 1))
                let target = ns.substring(with: match.range(at: 2))
                let ok = scheme == "help" ? ids.contains(target) : appTargets.contains(target)
                #expect(ok, "\(article.id) links to \(scheme):\(target)")
            }
        }
    }

    @Test func rendersHTML() throws {
        let article = try #require(HelpCenter.article("welcome"))
        let html = HelpCenter.html(for: article)
        #expect(html.contains("<h1>Welcome to CardStock</h1>"))
        #expect(html.contains(#"href="help:create-a-site""#))
        #expect(html.contains("<table>"))
    }
}
