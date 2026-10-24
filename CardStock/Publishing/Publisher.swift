import Foundation

/// Links a site folder to a GitHub repo and publishes it. All steps run off
/// the main thread. Content must be saved to disk before calling.
struct Publisher: Sendable {
    let root: URL
    let token: String
    /// Where to push instead of GitHub (tests use a local repo).
    var remoteOverride: String? = nil

    private var git: Git { Git(root: root, token: token) }

    struct Outcome: Sendable {
        /// The push brought in changes made elsewhere, so the site on disk changed.
        var pulledChanges: Bool
        var committed: Bool
    }

    // MARK: - Linking

    /// Sets up git in the folder (if needed), points it at an empty GitHub
    /// repo, and pushes everything. Returns the saved link.
    func link(repo: String, user: GitHubClient.User) async throws -> ProjectSettings.GitHubLink {
        try ensureGitignore()
        if !git.isRepository {
            try await git.run("init", "-b", "main")
        }
        let branch = (try? await git.run("symbolic-ref", "--short", "HEAD"))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "main"

        try await ensureIdentity(user)

        let link = ProjectSettings.GitHubLink(repo: repo, branch: branch.isEmpty ? "main" : branch)
        LocalData.setGitHubAccount(user.login, in: root)
        var settings = ProjectSettings.load(from: root)
        settings.github = link
        try settings.save(to: root)

        try buildSite()
        try await git.run("add", "-A")
        if try await hasStagedChanges() {
            try await git.run("commit", "-m", "Set up site with CardStock")
        }

        if (await git.attempt(["remote", "get-url", "origin"])).succeeded {
            try await git.run("remote", "set-url", "origin", link.remoteURL)
        } else {
            try await git.run("remote", "add", "origin", link.remoteURL)
        }
        try await git.run("push", "-u", "origin", "HEAD:\(link.branch)")
        return link
    }

    /// Removes the GitHub link. Keeps the folder's git history.
    func unlink() async throws {
        var settings = ProjectSettings.load(from: root)
        settings.github = nil
        try settings.save(to: root)
        if (await git.attempt(["remote", "get-url", "origin"])).succeeded {
            try await git.run("remote", "remove", "origin")
        }
    }

    // MARK: - Publishing

    /// Builds the site, commits, brings in changes from GitHub, and pushes.
    func publish(link: ProjectSettings.GitHubLink, user: GitHubClient.User,
                 message: String) async throws -> Outcome {
        if !git.isRepository {
            try await reconnect(link)
        }
        try await ensureIdentity(user)
        try buildSite()
        try await git.run("add", "-A")
        var committed = false
        if try await hasStagedChanges() {
            try await git.run("commit", "-m", try await commitMessage(message))
            committed = true
        }

        // Bring in anything pushed from another computer.
        let before = try await git.run("rev-parse", "HEAD")
        let remoteHeads = try await git.run("ls-remote", "--heads", "origin", link.branch)
        if !remoteHeads.isEmpty {
            try await pull(link.branch)
        }
        let pulled = try await git.run("rev-parse", "HEAD") != before

        // Pulled content changes the generated site, so rebuild it.
        if pulled {
            try buildSite()
            try await git.run("add", "-A")
            if try await hasStagedChanges() {
                try await git.run("commit", "-m", "Rebuild site")
                committed = true
            }
        }

        try await git.run("push", "origin", "HEAD:\(link.branch)")
        return Outcome(pulledChanges: pulled, committed: committed)
    }

    /// Sets up git again in a linked site folder that has none, such as one
    /// downloaded from GitHub as a ZIP or copied without its hidden `.git`
    /// folder. GitHub's history is taken as the starting point and the files
    /// on disk are left as they are, so only real edits get committed.
    private func reconnect(_ link: ProjectSettings.GitHubLink) async throws {
        try ensureGitignore()
        try await git.run("init", "-b", link.branch)
        // ZIP downloads and some drives change file permissions; don't
        // publish that as a change.
        try await git.run("config", "--local", "core.fileMode", "false")
        try await git.run("remote", "add", "origin", remoteOverride ?? link.remoteURL)
        let remoteHeads = try await git.run("ls-remote", "--heads", "origin", link.branch)
        if !remoteHeads.isEmpty {
            try await git.run("fetch", "origin", link.branch)
            // Moves to GitHub's latest commit without touching any files.
            try await git.run("reset", "FETCH_HEAD")
        }
    }

    /// Commits as the GitHub user with their private noreply address, unless
    /// this folder already has one. (The Mac-wide git email is ignored so a
    /// personal address never ends up in a public repo.)
    private func ensureIdentity(_ user: GitHubClient.User) async throws {
        let email = await git.attempt(["config", "--local", "user.email"])
        guard email.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        try await git.run("config", "--local", "user.name", user.name ?? user.login)
        try await git.run("config", "--local", "user.email", user.noreplyEmail)
    }

    /// Rebases local commits onto GitHub's. Conflicts in the generated
    /// `public/` folder are resolved automatically (it's rebuilt after);
    /// conflicts in content stop the publish.
    private func pull(_ branch: String) async throws {
        let result = await git.attempt(["pull", "--rebase", "origin", branch])
        if result.succeeded { return }
        guard isRebasing else {
            throw SiteError("Couldn't get changes from GitHub: \(result.error.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        for _ in 0..<50 {
            guard isRebasing else { break }
            let conflicted = try await git.run("diff", "--name-only", "--diff-filter=U")
                .split(separator: "\n").map(String.init)
            if conflicted.isEmpty {
                // Nothing left to resolve in this step; carry on.
                if (await git.attempt(["rebase", "--continue"])).succeeded { continue }
                if (await git.attempt(["rebase", "--skip"])).succeeded { continue }
                break
            }
            guard conflicted.allSatisfy({ $0.hasPrefix("public/") }) else {
                _ = await git.attempt(["rebase", "--abort"])
                let files = conflicted.filter { !$0.hasPrefix("public/") }.joined(separator: ", ")
                throw SiteError("""
                    GitHub has changes to the same files you changed here (\(files)). \
                    Nothing was published. This happens when the same site is edited on two computers \
                    without publishing in between.
                    """)
            }
            try await git.run(["checkout", "--theirs", "--"] + conflicted)
            try await git.run(["add", "--"] + conflicted)
            _ = await git.attempt(["rebase", "--continue"])
        }

        if isRebasing {
            _ = await git.attempt(["rebase", "--abort"])
            throw SiteError("Couldn't combine your changes with GitHub's. Nothing was published.")
        }
    }

    private var isRebasing: Bool {
        let gitDir = root.appending(path: ".git")
        let fm = FileManager.default
        return fm.fileExists(atPath: gitDir.appending(path: "rebase-merge").path)
            || fm.fileExists(atPath: gitDir.appending(path: "rebase-apply").path)
    }

    // MARK: - Helpers

    private func buildSite() throws {
        _ = try SiteBuilder.build(try Site.load(from: root))
    }

    private func hasStagedChanges() async throws -> Bool {
        let result = await git.attempt(["diff", "--cached", "--quiet"])
        switch result.status {
        case 0: return false
        case 1: return true
        default: throw Git.Failure(command: "diff", message: result.error)
        }
    }

    /// The user's message (if any), followed by a list of changed source files.
    private func commitMessage(_ message: String) async throws -> String {
        let status = try await git.run("diff", "--cached", "--name-status", "--no-renames")
        var added: [String] = [], edited: [String] = [], removed: [String] = []
        for line in status.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2, !parts[1].hasPrefix("public/") else { continue }
            switch parts[0].first {
            case "A": added.append(parts[1])
            case "D": removed.append(parts[1])
            default: edited.append(parts[1])
            }
        }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        var text = trimmed.isEmpty ? "Update site from CardStock" : trimmed
        var details: [String] = []
        if !added.isEmpty { details.append("Added: " + added.joined(separator: ", ")) }
        if !edited.isEmpty { details.append("Edited: " + edited.joined(separator: ", ")) }
        if !removed.isEmpty { details.append("Removed: " + removed.joined(separator: ", ")) }
        if !details.isEmpty { text += "\n\n" + details.joined(separator: "\n") }
        return text
    }

    /// Makes sure macOS/exFAT clutter and build scratch never get committed.
    private func ensureGitignore() throws {
        let url = root.appending(path: ".gitignore")
        var text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let existing = Set(text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) })
        let needed = [".DS_Store", "._*", ".public-building/"].filter { !existing.contains($0) }
        guard !needed.isEmpty else { return }
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        text += needed.joined(separator: "\n") + "\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
