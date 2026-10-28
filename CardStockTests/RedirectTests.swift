import Foundation
import Testing
@testable import CardStock

struct RedirectTests {
    @Test func redirectsAwayFromPagesAreDropped() {
        let text = "# moved\n/videos/ /pages/videos/ 301\n/pages/videos/ /videos/ 301\n/old /pages/about/ 301\n/blog/* /news/:splat 301\n"
        let kept = SiteMigration.redirects(text, keepingPages: ["/videos/", "/pages/about/", "/blog/"])
        #expect(kept == "# moved\n/pages/videos/ /videos/ 301\n/old /pages/about/ 301\n/blog/* /news/:splat 301\n")
        #expect(SiteMigration.redirectSource("/videos/index.html /x/ 301") == "/videos/")
    }

    @Test func buildRemovesALoop() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "cardstock-redirects-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = dir.appending(path: "Site")
        try StarterSite.create(at: root, title: "Loop")
        try FileManager.default.createDirectory(at: root.appending(path: "static"), withIntermediateDirectories: true)
        try "/pages/about/ /about/ 301\n/about/ /pages/about/ 301\n".write(to: root.appending(path: "static/_redirects"), atomically: true, encoding: .utf8)
        let report = try SiteBuilder.build(try Site.load(from: root))
        let published = try String(contentsOf: root.appending(path: "public/_redirects"), encoding: .utf8)
        #expect(published == "/about/ /pages/about/ 301\n")
        #expect(try String(contentsOf: root.appending(path: "static/_redirects"), encoding: .utf8) == published)
        #expect(report.warnings.contains { $0.contains("_redirects") })
    }
}
