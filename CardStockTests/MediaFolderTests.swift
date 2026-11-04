import Foundation
import Testing
@testable import CardStock

/// Folders in media/: making, moving and renaming them, moving files, and
/// keeping links to moved files working.
struct MediaFolderTests {
    let dir = FileManager.default.temporaryDirectory.appending(path: "cardstock-folders-\(UUID().uuidString)")

    private func site() throws -> URL {
        let root = dir.appending(path: "Site")
        try StarterSite.create(at: root, title: "Site")
        let files = root.appending(path: "media/files")
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        for name in ["beach.jpg", "beach-small.jpg", "menu.pdf"] {
            try Data("x".utf8).write(to: files.appending(path: name))
        }
        try """
        ---
        title: Trip
        cover: /media/files/beach.jpg
        ---
        [![Beach](/media/files/beach-small.jpg)](/media/files/beach.jpg)

        [Menu](/media/files/menu.pdf?v=2) and <img src="/media/files/beach.jpg">. Not this: /media/files/beach.jpgs
        """.write(to: root.appending(path: "pages/trip.md"), atomically: true, encoding: .utf8)
        return root
    }

    private func file(_ path: String, in root: URL) throws -> MediaFile {
        try #require(MediaLibrary.scan(try Site.load(from: root)).first { $0.path == path })
    }

    @Test func makesFoldersWithWebSafeNames() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = try site()
        let photos = try MediaLibrary.makeFolder("Product Photos", in: "media", root: root)
        #expect(photos == "media/product-photos")
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "media/product-photos/.gitkeep").path))
        #expect(try MediaLibrary.makeFolder("product photos", in: "media", root: root) == "media/product-photos-2")
        #expect(try MediaLibrary.makeFolder("2026", in: photos, root: root) == "media/product-photos/2026")
        #expect(MediaLibrary.folders(in: root) == ["media/files", "media/product-photos", "media/product-photos/2026", "media/product-photos-2"])
        #expect(throws: SiteError.self) { try MediaLibrary.makeFolder("!!!", in: "media", root: root) }
        #expect(throws: SiteError.self) { try MediaLibrary.makeFolder("x", in: "pages", root: root) }
        // Empty folders aren't files.
        #expect(!MediaLibrary.scan(try Site.load(from: root)).contains { $0.name == ".gitkeep" })
    }

    @Test func movingFilesKeepsLinksAndTags() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = try site()
        var tags = MediaTags()
        tags["media/files/beach.jpg"] = ["Summer"]
        try tags.save(to: root)
        let photos = try MediaLibrary.makeFolder("photos", in: "media", root: root)

        let beach = try file("media/files/beach.jpg", in: root)
        #expect(beach.smallPath == "media/files/beach-small.jpg")
        let moves = try MediaLibrary.move([beach], to: photos, root: root)
        #expect(moves == ["media/files/beach.jpg": "media/photos/beach.jpg",
                          "media/files/beach-small.jpg": "media/photos/beach-small.jpg"])
        try MediaLibrary.updateReferences(moves, root: root)

        let text = try String(contentsOf: root.appending(path: "pages/trip.md"), encoding: .utf8)
        #expect(text.contains("cover: /media/photos/beach.jpg"))
        #expect(text.contains("[![Beach](/media/photos/beach-small.jpg)](/media/photos/beach.jpg)"))
        #expect(text.contains(#"<img src="/media/photos/beach.jpg">"#))
        #expect(text.contains("(/media/files/menu.pdf?v=2)"))
        #expect(text.contains("/media/files/beach.jpgs"), "only whole paths change")
        #expect(MediaTags.load(from: root)["media/photos/beach.jpg"] == ["Summer"])

        // A name that's taken gets a number, for both sizes.
        try Data("y".utf8).write(to: root.appending(path: "media/files/beach.jpg"))
        let second = try MediaLibrary.move([try file("media/files/beach.jpg", in: root)], to: photos, root: root)
        #expect(second == ["media/files/beach.jpg": "media/photos/beach-2.jpg"])
    }

    @Test func renamingAndMovingFolders() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = try site()
        let renamed = try MediaLibrary.renameFolder("media/files", to: "Uploads", root: root)
        #expect(renamed.path == "media/uploads")
        #expect(renamed.moves["media/files/menu.pdf"] == "media/uploads/menu.pdf")
        #expect(renamed.moves.count == 3)
        try MediaLibrary.updateReferences(renamed.moves, root: root)
        var text = try String(contentsOf: root.appending(path: "pages/trip.md"), encoding: .utf8)
        #expect(text.contains("/media/uploads/menu.pdf?v=2"))
        #expect(!text.contains("/media/files/beach.jpg)"))

        // Only the capitals change: still works on Mac drives.
        let capital = try MediaLibrary.renameFolder("media/uploads", to: "UPLOADS", root: root)
        #expect(capital.path == "media/uploads" && capital.moves.isEmpty)

        let archive = try MediaLibrary.makeFolder("archive", in: "media", root: root)
        let moved = try MediaLibrary.moveFolder("media/uploads", into: archive, root: root)
        #expect(moved.path == "media/archive/uploads")
        try MediaLibrary.updateReferences(moved.moves, root: root)
        text = try String(contentsOf: root.appending(path: "pages/trip.md"), encoding: .utf8)
        #expect(text.contains("cover: /media/archive/uploads/beach.jpg"))

        #expect(throws: SiteError.self) { try MediaLibrary.moveFolder(archive, into: "media/archive/uploads", root: root) }
        #expect(throws: SiteError.self) { try MediaLibrary.renameFolder("media", to: "x", root: root) }
    }

    @Test func rewritesEncodedAndBareReferences() {
        let moves = ["media/my files/a b.jpg": "media/new/a b.jpg", "media/x.png": "media/y/x.png"]
        #expect(MediaLibrary.rewriteReferences(in: "![](/media/my%20files/a%20b.jpg)", moves) == "![](/media/new/a%20b.jpg)")
        #expect(MediaLibrary.rewriteReferences(in: #"{"logo": "media/x.png#top"}"#, moves) == #"{"logo": "media/y/x.png#top"}"#)
        #expect(MediaLibrary.rewriteReferences(in: "nothing here", moves) == "nothing here")
    }
}
