import Foundation
import Testing
@testable import CardStock

struct FilesTests {
    let dir = FileManager.default.temporaryDirectory.appending(path: "cardstock-files-\(UUID().uuidString)")

    private func write(_ path: String, in root: URL, bytes: Int = 3) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: bytes).write(to: url)
    }

    private func makeSite() throws -> URL {
        let root = dir.appending(path: "Site")
        try StarterSite.create(at: root, title: "Site")
        return root
    }

    @Test func listsFilesWithUsage() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = try makeSite()
        try write("media/posts/hello-world/beach.jpg", in: root, bytes: 10)
        try write("media/posts/hello-world/beach-small.jpg", in: root, bytes: 4)
        try write("media/files/guide.pdf", in: root)
        try write("media/Dropped In Finder.png", in: root)
        let post = root.appending(path: "pages/hello-world.md")
        try (try String(contentsOf: post, encoding: .utf8) + "\n[![B](/media/posts/hello-world/beach-small.jpg)](/media/posts/hello-world/beach.jpg)\n")
            .write(to: post, atomically: true, encoding: .utf8)

        let files = MediaLibrary.scan(try Site.load(from: root))
        #expect(Set(files.map(\.path)) == ["media/posts/hello-world/beach.jpg", "media/files/guide.pdf", "media/Dropped In Finder.png"])
        let beach = try #require(files.first { $0.name == "beach.jpg" })
        #expect(beach.smallPath == "media/posts/hello-world/beach-small.jpg")
        #expect(beach.size == 14)
        #expect(beach.usedIn == ["Hello, world"])
        #expect(files.first { $0.name == "guide.pdf" }?.usedIn.isEmpty == true)
    }

    @Test func markdownForEachKind() {
        func file(_ path: String, small: String? = nil) -> MediaFile {
            MediaFile(path: path, smallPath: small, size: 0, added: .now, usedIn: [])
        }
        #expect(MediaLibrary.markdown(for: file("media/a/beach-day.jpg", small: "media/a/beach-day-small.jpg"))
                == "[![Beach day](/media/a/beach-day-small.jpg)](/media/a/beach-day.jpg)")
        #expect(MediaLibrary.markdown(for: file("media/icon.png")) == "![Icon](/media/icon.png)")
        #expect(MediaLibrary.markdown(for: file("media/files/user_guide.pdf")) == "[User guide](/media/files/user_guide.pdf)")
        #expect(MediaLibrary.markdown(for: file("media/My Photo.jpg")) == "![My Photo](/media/My%20Photo.jpg)")
        // The address round-trips to the file it came from.
        #expect(MediaLibrary.referencedPaths(in: "![x](/media/My%20Photo.jpg)") == ["media/My Photo.jpg"])
    }

    @Test func addsFilesWithoutOverwriting() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = try makeSite()
        try write("incoming/Annual Report.PDF", in: dir)
        let source = dir.appending(path: "incoming/Annual Report.PDF")
        #expect(try MediaLibrary.addFiles([source], to: root) == ["media/files/annual-report.pdf"])
        #expect(try MediaLibrary.addFiles([source], to: root) == ["media/files/annual-report-2.pdf"])
    }

    @Test func pairsOnlyMatchingSmallFiles() {
        #expect(MediaLibrary.smallPath(for: "media/a/b.jpg") == "media/a/b-small.jpg")
        #expect(MediaLibrary.largePath(forSmall: "media/a/b-small.jpg") == "media/a/b.jpg")
        #expect(MediaLibrary.largePath(forSmall: "media/a/b.jpg") == nil)
    }

    @MainActor @Test func watcherNoticesFilesAddedElsewhere() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = dir.appending(path: "Watched")
        try FileManager.default.createDirectory(at: folder.appending(path: "media"), withIntermediateDirectories: true)
        var changes = 0
        let watcher = try #require(FolderWatcher(url: folder, latency: 0.1) { changes += 1 })
        try await Task.sleep(for: .milliseconds(300))
        try write("media/new.png", in: folder)
        for _ in 0..<50 where changes == 0 {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(changes > 0)
        _ = watcher
    }
}

struct StorageTests {
    @Test func measuresFoldersAndFlagsLargeFiles() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "cardstock-storage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        for (path, bytes) in [("media/a.jpg", 1000), ("public/index.html", 200), ("public/media/a.jpg", 1000),
                              (".git/objects/x", 500), ("media/video.mov", 26 * 1024 * 1024)] {
            let url = root.appending(path: path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(count: bytes).write(to: url)
        }
        let storage = SiteStorage.measure(root: root)
        #expect(storage.gitBytes == 500)
        #expect(storage.mediaBytes == 1000 + 26 * 1024 * 1024)
        #expect(storage.publicBytes == 1200)
        #expect(storage.publicFileCount == 2)
        #expect(storage.largeFiles.map(\.path) == ["media/video.mov"])
    }
}

struct DuplicateTests {
    @Test func duplicatesBothSizes() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "cardstock-dup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "media/posts/trip")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("L".utf8).write(to: folder.appending(path: "beach.jpg"))
        try Data("S".utf8).write(to: folder.appending(path: "beach-small.jpg"))
        let file = MediaFile(path: "media/posts/trip/beach.jpg", smallPath: "media/posts/trip/beach-small.jpg",
                             size: 2, added: .now, usedIn: [])
        #expect(try MediaLibrary.duplicate(file, root: root) == "media/posts/trip/beach-copy.jpg")
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "beach-copy-small.jpg").path))
        #expect(try MediaLibrary.duplicate(file, root: root) == "media/posts/trip/beach-copy-2.jpg")
    }
}
