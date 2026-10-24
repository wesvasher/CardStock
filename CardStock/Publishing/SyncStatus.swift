import Foundation

/// How a linked site on this Mac compares with its GitHub repository.
struct SyncStatus: Sendable, Equatable {
    /// Source files changed on this Mac and not yet published (excludes the
    /// generated `public/` folder).
    var changedFiles: [String] = []
    /// Snapshots saved here but not yet on GitHub.
    var ahead = 0
    /// Snapshots on GitHub (e.g. from another computer) not yet here.
    var behind = 0
    /// The snapshots on GitHub that aren't here yet, newest first (at most 5).
    var incoming: [Snapshot] = []
    /// Source files those snapshots changed (excludes `public/`).
    var incomingFiles: [String] = []
    /// Latest snapshot on GitHub.
    var remoteMessage: String?
    var remoteDate: Date?
    /// When GitHub was last contacted successfully, or nil if it couldn't be reached.
    var checkedAt: Date?
    var fetchError: String?

    struct Snapshot: Sendable, Equatable {
        /// First line of the commit message.
        var message: String
        var date: Date?
    }

    var hasLocalChanges: Bool { !changedFiles.isEmpty || ahead > 0 }

    /// Files changed both here and on GitHub. Publishing stops when these
    /// conflict, so they're worth a warning before it happens.
    var overlappingFiles: [String] {
        let incoming = Set(incomingFiles)
        return changedFiles.filter { incoming.contains($0) }
    }
    var isUpToDate: Bool { !hasLocalChanges && behind == 0 && checkedAt != nil }

    /// Number shown on the sidebar badge.
    var pendingCount: Int { changedFiles.isEmpty ? ahead : changedFiles.count }

    /// Compares the folder with GitHub. With `fetch`, contacts GitHub first
    /// for its latest state; otherwise uses what was last fetched.
    static func check(root: URL, token: String?, branch: String, fetch: Bool,
                      previous: SyncStatus? = nil) async -> SyncStatus {
        let git = Git(root: root, token: token)
        var status = SyncStatus()
        status.checkedAt = previous?.checkedAt

        if fetch {
            if token == nil {
                status.fetchError = "Sign in to check GitHub."
            } else {
                let result = await git.attempt(["fetch", "--quiet", "origin", branch])
                if result.succeeded {
                    status.checkedAt = .now
                } else {
                    status.checkedAt = nil
                    status.fetchError = "Couldn't reach GitHub. Check your internet connection."
                }
            }
        } else {
            status.fetchError = previous?.fetchError
        }

        let porcelain = (try? await git.run("status", "--porcelain", "-uall")) ?? ""
        status.changedFiles = porcelain.split(separator: "\n").compactMap { line in
            guard line.count > 3 else { return nil }
            var path = String(line.dropFirst(3))
            if let arrow = path.range(of: " -> ") { path = String(path[arrow.upperBound...]) }
            path = path.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return path.hasPrefix("public/") ? nil : path
        }

        let remoteRef = "origin/\(branch)"
        if (await git.attempt(["rev-parse", "--verify", "--quiet", remoteRef])).succeeded {
            let counts = (try? await git.run("rev-list", "--left-right", "--count", "HEAD...\(remoteRef)")) ?? ""
            let parts = counts.split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
            if parts.count == 2 { (status.ahead, status.behind) = (parts[0], parts[1]) }
            if status.behind > 0 {
                let incoming = (try? await git.run("log", "-5", "--format=%s%x1f%ct", "HEAD..\(remoteRef)")) ?? ""
                status.incoming = incoming.split(separator: "\n").map { line in
                    let parts = line.components(separatedBy: "\u{1f}")
                    return Snapshot(message: parts[0],
                                    date: parts.count > 1 ? TimeInterval(parts[1]).map(Date.init(timeIntervalSince1970:)) : nil)
                }
                // Three dots: what GitHub changed since the two copies split.
                let files = (try? await git.run("diff", "--name-only", "--no-renames", "HEAD...\(remoteRef)")) ?? ""
                status.incomingFiles = files.split(separator: "\n").map(String.init).filter { !$0.hasPrefix("public/") }
            }
            let log = (try? await git.run("log", "-1", "--format=%s%x1f%ct", remoteRef)) ?? ""
            let fields = log.trimmingCharacters(in: .newlines).components(separatedBy: "\u{1f}")
            if fields.count == 2 {
                status.remoteMessage = fields[0]
                if let seconds = TimeInterval(fields[1]) { status.remoteDate = Date(timeIntervalSince1970: seconds) }
            }
        } else if let count = Int(((try? await git.run("rev-list", "--count", "HEAD")) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)) {
            // Never pushed: everything here is unpublished.
            status.ahead = count
        }
        return status
    }
}

/// For sites not linked to GitHub: whether `public/` reflects the latest edits.
struct BuildState: Sendable, Equatable {
    var lastBuild: Date?
    var changedSinceBuild: Bool

    static func check(root: URL) -> BuildState {
        let fm = FileManager.default
        let publicDir = root.appending(path: "public")
        let lastBuild = (try? fm.attributesOfItem(atPath: publicDir.path)[.modificationDate]) as? Date
        guard let lastBuild else { return BuildState(lastBuild: nil, changedSinceBuild: true) }

        let sources = ["site.json", "pages", "theme", "media", "static"]
        for name in sources {
            let url = root.appending(path: name)
            if let date = newestModification(url), date > lastBuild {
                return BuildState(lastBuild: lastBuild, changedSinceBuild: true)
            }
        }
        return BuildState(lastBuild: lastBuild, changedSinceBuild: false)
    }

    private static func newestModification(_ url: URL) -> Date? {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        var newest = (try? url.resourceValues(forKeys: Set(keys)))?.contentModificationDate
        if let e = fm.enumerator(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) {
            for case let file as URL in e {
                if let d = (try? file.resourceValues(forKeys: Set(keys)))?.contentModificationDate,
                   d > (newest ?? .distantPast) {
                    newest = d
                }
            }
        }
        return newest
    }
}
