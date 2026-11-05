import Foundation
import Testing
@testable import CardStock

/// Folders in the Pages list: paths, moving and renaming, and where
/// they're saved (front matter and site.json).
struct PageFolderTests {
    @Test func paths() {
        #expect(PageFolders.parent(of: "Recipes/Soups") == "Recipes")
        #expect(PageFolders.parent(of: "Recipes") == "")
        #expect(PageFolders.name(of: "Recipes/Soups") == "Soups")
        #expect(PageFolders.ancestors(of: "A/B/C") == ["A", "A/B", "A/B/C"])
        #expect(PageFolders.ancestors(of: "") == [])
        #expect(PageFolders.isInside("A/B", "A"))
        #expect(!PageFolders.isInside("AB", "A"))
        #expect(PageFolders.isInside("A", ""))
        #expect(PageFolders.normalized(" A / /B ") == "A/B")
    }

    @Test func names() {
        #expect(PageFolders.name(for: "  Summer Trips ") == "Summer Trips")
        #expect(PageFolders.name(for: "a/b") == "a-b")
        #expect(PageFolders.name(for: "   ") == nil)
    }

    @Test func allFoldersIncludeParentsInOrder() {
        let all = PageFolders.all(saved: ["Work", "Recipes/Soups", "Work"], pages: ["Recipes", "", "Work/2026", "Art"])
        #expect(all == ["Art", "Recipes", "Recipes/Soups", "Work", "Work/2026"])
        #expect(PageFolders.children(of: "", in: ["A", "A/B", "C"]) == ["A", "C"])
        #expect(PageFolders.children(of: "A", in: ["A", "A/B", "C"]) == ["A/B"])
    }

    @Test func moving() {
        #expect(PageFolders.moved("A/B/C", from: "A/B", to: "X") == "X/C")
        #expect(PageFolders.moved("A/B", from: "A/B", to: "X/B") == "X/B")
        // Removing A/B: what's in it moves up into A.
        #expect(PageFolders.moved("A/B/C", from: "A/B", to: "A") == "A/C")
        #expect(PageFolders.moved("A/B", from: "A/B", to: "") == "")
        #expect(PageFolders.moved("A/BC", from: "A/B", to: "X") == "A/BC")
        #expect(PageFolders.moved("Other", from: "A", to: "X") == "Other")
    }

    @Test func moveProblems() {
        let all = ["A", "A/B", "C"]
        #expect(PageFolders.moveProblem(from: "A", to: "A/B/A", in: all) != nil)
        #expect(PageFolders.moveProblem(from: "A/B", to: "C", in: all) != nil)
        #expect(PageFolders.moveProblem(from: "A/B", to: "C/B", in: all) == nil)
        #expect(PageFolders.moveProblem(from: "A", to: "A", in: all) == nil)
    }

    @Test func folderIsFrontMatter() {
        var item = ContentItem(fileURL: URL(filePath: "/tmp/pages/soup.md"), text: "---\ntitle: Soup\n---\nHot.")
        #expect(item.folder == "")
        item.folder = "Recipes/Soups"
        #expect(item.frontMatter.string("folder") == "Recipes/Soups")
        item.folder = ""
        #expect(item.frontMatter.string("folder") == nil)
    }

    @Test func savedInSiteJSON() throws {
        var config = SiteConfig()
        config.pageFolders = ["Recipes", "Recipes/Soups"]
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(SiteConfig.self, from: data).pageFolders == ["Recipes", "Recipes/Soups"])
        // Older site.json files have none.
        #expect(try JSONDecoder().decode(SiteConfig.self, from: Data("{}".utf8)).pageFolders == [])
    }
}
