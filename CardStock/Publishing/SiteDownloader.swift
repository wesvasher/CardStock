import Foundation

/// Downloads a site from GitHub onto this Mac with `git clone`, so it comes
/// with its full history and is ready to publish.
enum SiteDownloader {
    /// Clones `link.repo` into `folder` (which must not exist yet), sets the
    /// commit identity and makes sure the project file has the GitHub link.
    /// `remoteOverride` replaces the GitHub address (tests use a local repo).
    static func download(_ link: ProjectSettings.GitHubLink, to folder: URL, token: String,
                         user: GitHubClient.User, remoteOverride: String? = nil) async throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: folder.path) else {
            throw SiteError("There's already a folder named “\(folder.lastPathComponent)” there. Choose another place.")
        }
        let parent = folder.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)

        let remote = remoteOverride ?? link.remoteURL
        let result = await Git(root: parent, token: token)
            .attempt(["clone", "--branch", link.branch, remote, folder.path])
        guard result.succeeded else {
            try? fm.removeItem(at: folder)
            throw SiteError("Couldn't download \(link.repo): \(redacted(result.error, token))")
        }
        guard Site.isSite(folder) else {
            try? fm.removeItem(at: folder)
            throw SiteError("\(link.repo) doesn't have a CardStock site in it (there's no site.json file).")
        }

        // Commit as the GitHub user with their private noreply address.
        let git = Git(root: folder, token: token)
        try await git.run("config", "--local", "user.name", user.name ?? user.login)
        try await git.run("config", "--local", "user.email", user.noreplyEmail)

        // The project file normally already has the link; add it if not.
        var settings = ProjectSettings.load(from: folder)
        if settings.github != link {
            settings.github = link
            try settings.save(to: folder)
        }
        // Publish from this Mac with the account it was downloaded with.
        LocalData.setGitHubAccount(user.login, in: folder)
    }

    /// Where downloaded sites go unless the user picks another place.
    static var defaultParent: URL {
        URL.documentsDirectory.appending(path: "CardStock", directoryHint: .isDirectory)
    }

    /// A folder name for a repository: its name without the owner.
    static func folderName(for repo: String) -> String {
        let name = repo.split(separator: "/").last.map(String.init) ?? repo
        return name.isEmpty ? "Site" : name
    }

    private static func redacted(_ text: String, _ token: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? trimmed : trimmed.replacingOccurrences(of: token, with: "••••")
    }
}
