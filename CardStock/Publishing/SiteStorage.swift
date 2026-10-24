import Foundation

/// How much space a site takes, for keeping an eye on GitHub's and
/// Cloudflare's limits.
struct SiteStorage: Equatable, Sendable {
    struct LargeFile: Equatable, Sendable, Identifiable {
        var path: String
        var bytes: Int64
        var id: String { path }
    }

    /// The `.git` folder: every saved version of the site on this Mac. Nil
    /// when the site has never been linked to GitHub.
    var gitBytes: Int64?
    var mediaBytes: Int64 = 0
    /// The built website in `public/`.
    var publicBytes: Int64 = 0
    var publicFileCount = 0
    /// Files that are over one of the limits below, biggest first.
    var largeFiles: [LargeFile] = []

    // Limits (checked October 2026).
    /// GitHub suggests keeping a repository under about 1 GB.
    static let githubRecommendedRepoBytes: Int64 = 1_000_000_000
    /// GitHub warns about files over 50 MB when they're pushed...
    static let githubWarnFileBytes: Int64 = 50_000_000
    /// ...and refuses files over 100 MB.
    static let githubMaxFileBytes: Int64 = 100_000_000
    /// Cloudflare Pages won't serve a file over 25 MiB.
    static let cloudflareMaxFileBytes: Int64 = 25 * 1024 * 1024
    /// Cloudflare Pages' file limit per site on the free plan.
    static let cloudflareMaxFiles = 20_000

    /// Measures the site folder. Reads every file's size, so run it off the
    /// main thread.
    static func measure(root: URL) -> SiteStorage {
        var storage = SiteStorage()
        let git = root.appending(path: ".git")
        if FileManager.default.fileExists(atPath: git.path) {
            storage.gitBytes = folderSize(git).bytes
        }
        storage.mediaBytes = folderSize(root.appending(path: "media")).bytes
        let built = folderSize(root.appending(path: "public"))
        storage.publicBytes = built.bytes
        storage.publicFileCount = built.files

        // Large files anywhere in the site except .git and public/ (which
        // only holds copies).
        let skip: Set<String> = [".git", "public", ".public-building", LocalData.folderName]
        let base = root.standardizedFileURL.path + "/"
        if let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) {
            for case let url as URL in walker {
                if skip.contains(url.lastPathComponent) {
                    walker.skipDescendants()
                    continue
                }
                guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                      values.isRegularFile == true, let size = values.fileSize,
                      Int64(size) > cloudflareMaxFileBytes
                else { continue }
                let path = url.standardizedFileURL.path
                storage.largeFiles.append(LargeFile(path: path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path,
                                                    bytes: Int64(size)))
            }
        }
        storage.largeFiles.sort { $0.bytes > $1.bytes }
        return storage
    }

    /// Total size and number of files in a folder (0 when it's missing).
    static func folderSize(_ url: URL) -> (bytes: Int64, files: Int) {
        guard let walker = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey])
        else { return (0, 0) }
        var bytes: Int64 = 0, files = 0
        for case let file as URL in walker {
            guard let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            bytes += Int64(values.fileSize ?? values.totalFileAllocatedSize ?? 0)
            files += 1
        }
        return (bytes, files)
    }
}
