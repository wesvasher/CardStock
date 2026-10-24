import Foundation
import Testing
@testable import CardStock

/// Exercises publishing against a local bare repo standing in for GitHub.
struct PublisherTests {
    let base = FileManager.default.temporaryDirectory.appending(path: "cardstock-pub-\(UUID().uuidString)")
    let link = ProjectSettings.GitHubLink(repo: "test/site", branch: "main")
    let user = GitHubClient.User(login: "tester", id: 1, name: "Tester", avatarURL: nil)

    private func makeClone(_ name: String, remote: URL) async throws -> URL {
        let dir = base.appending(path: name)
        try await Git(root: base).run("clone", "-q", remote.path, dir.path)
        let git = Git(root: dir)
        try await git.run("config", "user.name", "Test")
        try await git.run("config", "user.email", "test@example.com")
        return dir
    }

    private func setSummary(_ root: URL, _ file: String, _ summary: String) throws {
        let url = root.appending(path: file)
        var item = ContentItem(fileURL: url, text: try String(contentsOf: url, encoding: .utf8))
        item.frontMatter.setString("summary", summary)
        try item.fileText.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func publishesAndMergesChangesFromAnotherComputer() async throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let remote = base.appending(path: "remote.git")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try await Git(root: base).run("init", "-q", "--bare", "-b", "main", remote.path)

        // Computer A creates the site and publishes it.
        let a = base.appending(path: "a")
        try StarterSite.create(at: a, title: "Two Macs")
        let gitA = Git(root: a)
        try await gitA.run("init", "-q", "-b", "main")
        try await gitA.run("config", "user.name", "Test")
        try await gitA.run("config", "user.email", "test@example.com")
        try await gitA.run("remote", "add", "origin", remote.path)
        try "---\ntype: post\ntitle: Second\ndate: 2026-02-01\n---\nTwo".write(
            to: a.appending(path: "pages/second.md"), atomically: true, encoding: .utf8)
        var outcome = try await Publisher(root: a, token: "").publish(link: link, user: user, message: "First")
        #expect(outcome.committed)
        #expect(!outcome.pulledChanges)
        let log = try await gitA.run("log", "-1", "--format=%B")
        #expect(log.hasPrefix("First\n"))
        #expect(log.contains("pages/hello-world.md"))
        #expect(!log.contains("public/"))

        // Computer B edits one post and publishes.
        let b = try await makeClone("b", remote: remote)
        try setSummary(b, "pages/second.md", "Edited on B")
        outcome = try await Publisher(root: b, token: "").publish(link: link, user: user, message: "")
        #expect(outcome.committed)

        // Meanwhile A edits a different post. Both changed public/index.html,
        // which must be resolved automatically.
        try setSummary(a, "pages/hello-world.md", "Edited on A")
        outcome = try await Publisher(root: a, token: "").publish(link: link, user: user, message: "")
        #expect(outcome.pulledChanges)

        let home = try String(contentsOf: a.appending(path: "public/index.html"), encoding: .utf8)
        #expect(home.contains("Edited on A"))
        #expect(home.contains("Edited on B"))
        let status = try await gitA.run("status", "--porcelain")
        #expect(status.isEmpty)
        let local = try await gitA.run("rev-parse", "HEAD")
        let pushed = try await Git(root: remote).run("rev-parse", "main")
        #expect(local == pushed)

        // Publishing with nothing new is a no-op.
        outcome = try await Publisher(root: a, token: "").publish(link: link, user: user, message: "")
        #expect(!outcome.committed && !outcome.pulledChanges)
    }

    /// A site downloaded from GitHub as a ZIP has no .git folder. Publishing
    /// sets git up again on top of GitHub's history, so only real edits are
    /// committed.
    @Test func publishesFromAFolderWithoutGit() async throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let remote = base.appending(path: "remote.git")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try await Git(root: base).run("init", "-q", "--bare", "-b", "main", remote.path)

        let a = base.appending(path: "a")
        try StarterSite.create(at: a, title: "Zip")
        let gitA = Git(root: a)
        try await gitA.run("init", "-q", "-b", "main")
        try await gitA.run("remote", "add", "origin", remote.path)
        _ = try await Publisher(root: a, token: "").publish(link: link, user: user, message: "First")

        // The "ZIP": the same files with no .git folder, one post edited.
        let zip = base.appending(path: "zip")
        try FileManager.default.copyItem(at: a, to: zip)
        try FileManager.default.removeItem(at: zip.appending(path: ".git"))
        try setSummary(zip, "pages/hello-world.md", "Edited after download")

        var publisher = Publisher(root: zip, token: "")
        publisher.remoteOverride = remote.path
        let outcome = try await publisher.publish(link: link, user: user, message: "From the ZIP")
        #expect(outcome.committed)

        let gitZip = Git(root: zip)
        let changed = try await gitZip.run("show", "--name-only", "--format=", "HEAD")
            .split(separator: "\n").filter { !$0.hasPrefix("public/") }
        #expect(changed == ["pages/hello-world.md"])
        #expect(try await gitZip.run("rev-list", "--count", "HEAD").hasPrefix("2"))
        #expect(try await gitZip.run("log", "-1", "--format=%ae").hasPrefix(user.noreplyEmail))
        let pushed = try await Git(root: remote).run("rev-parse", "main")
        #expect(try await gitZip.run("rev-parse", "HEAD") == pushed)
    }

    /// Open from GitHub: the clone has its history, the noreply identity and
    /// the GitHub link, and publishes like any other copy.
    @Test func downloadsASiteFromGitHub() async throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let remote = base.appending(path: "remote.git")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try await Git(root: base).run("init", "-q", "--bare", "-b", "main", remote.path)

        let a = base.appending(path: "a")
        try StarterSite.create(at: a, title: "Download")
        let gitA = Git(root: a)
        try await gitA.run("init", "-q", "-b", "main")
        try await gitA.run("remote", "add", "origin", remote.path)
        _ = try await Publisher(root: a, token: "").publish(link: link, user: user, message: "First")

        let folder = base.appending(path: "Sites/site")
        try await SiteDownloader.download(link, to: folder, token: "", user: user, remoteOverride: remote.path)
        #expect(Site.isSite(folder))
        #expect(ProjectSettings.load(from: folder).github == link)
        #expect(LocalData.gitHubAccount(in: folder) == user.login)
        let gitB = Git(root: folder)
        #expect(try await gitB.run("config", "--local", "user.email").hasPrefix(user.noreplyEmail))
        #expect(try await gitB.run("rev-parse", "HEAD") == (try await gitA.run("rev-parse", "HEAD")))

        // A folder that's already there is never overwritten.
        await #expect(throws: SiteError.self) {
            try await SiteDownloader.download(link, to: folder, token: "", user: user, remoteOverride: remote.path)
        }
        #expect(SiteDownloader.folderName(for: "someone/my-site") == "my-site")
    }

    @Test func stopsOnContentConflict() async throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let remote = base.appending(path: "remote.git")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try await Git(root: base).run("init", "-q", "--bare", "-b", "main", remote.path)

        let a = base.appending(path: "a")
        try StarterSite.create(at: a, title: "Conflict")
        let gitA = Git(root: a)
        try await gitA.run("init", "-q", "-b", "main")
        try await gitA.run("config", "user.name", "Test")
        try await gitA.run("config", "user.email", "test@example.com")
        try await gitA.run("remote", "add", "origin", remote.path)
        _ = try await Publisher(root: a, token: "").publish(link: link, user: user, message: "")

        let b = try await makeClone("b", remote: remote)
        try setSummary(b, "pages/hello-world.md", "B's version")
        _ = try await Publisher(root: b, token: "").publish(link: link, user: user, message: "")

        try setSummary(a, "pages/hello-world.md", "A's version")
        await #expect(throws: SiteError.self) {
            try await Publisher(root: a, token: "").publish(link: link, user: user, message: "")
        }
        // A's work is kept and nothing is left half-merged.
        #expect(!FileManager.default.fileExists(atPath: a.appending(path: ".git/rebase-merge").path))
        let text = try String(contentsOf: a.appending(path: "pages/hello-world.md"), encoding: .utf8)
        #expect(text.contains("A's version"))
    }

    @Test func syncStatusTracksBothSides() async throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let remote = base.appending(path: "remote.git")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try await Git(root: base).run("init", "-q", "--bare", "-b", "main", remote.path)

        let a = base.appending(path: "a")
        try StarterSite.create(at: a, title: "Status")
        let gitA = Git(root: a)
        try await gitA.run("init", "-q", "-b", "main")
        try await gitA.run("config", "user.name", "Test")
        try await gitA.run("config", "user.email", "test@example.com")
        try await gitA.run("remote", "add", "origin", remote.path)

        // Never published: everything is local.
        var status = await SyncStatus.check(root: a, token: "", branch: "main", fetch: true)
        #expect(status.hasLocalChanges)
        #expect(!status.isUpToDate)

        _ = try await Publisher(root: a, token: "").publish(link: link, user: user, message: "First")
        status = await SyncStatus.check(root: a, token: "", branch: "main", fetch: true)
        #expect(status.isUpToDate)
        #expect(status.remoteMessage == "First")

        // A local edit shows up as an unpublished change; public/ is ignored.
        try setSummary(a, "pages/hello-world.md", "Changed")
        try SiteBuilder.build(try Site.load(from: a))
        status = await SyncStatus.check(root: a, token: "", branch: "main", fetch: false, previous: status)
        #expect(status.changedFiles == ["pages/hello-world.md"])
        #expect(status.pendingCount == 1)

        // Another computer publishes: A is behind after fetching.
        let b = try await makeClone("b", remote: remote)
        try setSummary(b, "pages/hello-world.md", "From B")
        try "x".write(to: b.appending(path: "pages/new.md"), atomically: true, encoding: .utf8)
        _ = try await Publisher(root: b, token: "").publish(link: link, user: user, message: "")
        try await gitA.run("checkout", "--", "pages/hello-world.md")
        status = await SyncStatus.check(root: a, token: "", branch: "main", fetch: true)
        #expect(status.behind == 1)
        #expect(!status.hasLocalChanges || status.changedFiles.isEmpty)

        // What came in, for the banner: the snapshot and the files it touched.
        #expect(status.incoming.count == 1)
        #expect(status.incoming.first?.date != nil)
        #expect(Set(status.incomingFiles) == ["pages/hello-world.md", "pages/new.md"])
        #expect(status.overlappingFiles.isEmpty)

        // Editing the same post here is flagged before publishing stops on it.
        try setSummary(a, "pages/hello-world.md", "Also edited on A")
        status = await SyncStatus.check(root: a, token: "", branch: "main", fetch: false, previous: status)
        #expect(status.overlappingFiles == ["pages/hello-world.md"])
    }
}

struct ScheduleTests {
    @Test func countdownFormats() {
        let now = Date(timeIntervalSince1970: 0)
        #expect(ScheduledPublish.countdown(to: now.addingTimeInterval(65), from: now) == "1m 05s")
        #expect(ScheduledPublish.countdown(to: now.addingTimeInterval(3 * 3600 + 4 * 60 + 5), from: now) == "3h 04m 05s")
        #expect(ScheduledPublish.countdown(to: now.addingTimeInterval(2 * 86_400 + 3600), from: now) == "2d 1h 00m 00s")
        #expect(ScheduledPublish.countdown(to: now.addingTimeInterval(-10), from: now) == "0m 00s")
    }

    @Test func savesAndRemoves() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "cardstock-schedule-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let schedule = ScheduledPublish(date: Date(timeIntervalSince1970: 2_000_000_000), message: "Hi")
        try ScheduledPublish.save(schedule, in: root)
        #expect(ScheduledPublish.load(from: root) == schedule)
        try ScheduledPublish.save(nil, in: root)
        #expect(ScheduledPublish.load(from: root) == nil)
    }
}

struct AccountTests {
    let mine = ProjectSettings.GitHubLink(repo: "wes/site", branch: "main")
    let hers = ProjectSettings.GitHubLink(repo: "jane/blog", branch: "main")
    let org = ProjectSettings.GitHubLink(repo: "family/photos", branch: "main")
    let logins = ["jane", "Wes"]

    @Test func picksTheRepoOwnersAccount() {
        #expect(GitHubAccounts.login(for: mine, chosen: nil, signedIn: logins, defaultLogin: "jane") == "Wes")
        #expect(GitHubAccounts.login(for: hers, chosen: nil, signedIn: logins, defaultLogin: "Wes") == "jane")
        // Someone else's repo (an organization, or shared with you): the default account.
        #expect(GitHubAccounts.login(for: org, chosen: nil, signedIn: logins, defaultLogin: "jane") == "jane")
    }

    @Test func aChosenAccountWins() {
        #expect(GitHubAccounts.login(for: hers, chosen: "wes", signedIn: logins, defaultLogin: nil) == "Wes")
        // Chosen but signed out: no account, rather than publishing as someone else.
        #expect(GitHubAccounts.login(for: hers, chosen: "bob", signedIn: logins, defaultLogin: "jane") == nil)
    }

    @Test func unlinkedSitesUseTheDefault() {
        #expect(GitHubAccounts.login(for: nil, chosen: nil, signedIn: logins, defaultLogin: "wes") == "Wes")
        #expect(GitHubAccounts.login(for: nil, chosen: nil, signedIn: logins, defaultLogin: nil) == "jane")
        #expect(GitHubAccounts.login(for: mine, chosen: nil, signedIn: [], defaultLogin: "wes") == nil)
    }

    @Test func choiceIsSavedPerMacAndKeptOutOfGit() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "cardstock-account-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        #expect(LocalData.gitHubAccount(in: root) == nil)
        LocalData.setGitHubAccount("jane", in: root)
        #expect(LocalData.gitHubAccount(in: root) == "jane")
        let ignore = try String(contentsOf: root.appending(path: ".gitignore"), encoding: .utf8)
        #expect(ignore.contains(".cardstock-local/"))
        LocalData.setGitHubAccount(nil, in: root)
        #expect(LocalData.gitHubAccount(in: root) == nil)
    }

    @Test func readsTheAvatarFromGitHub() throws {
        let json = #"{"login":"wes","id":7,"name":"Wes","avatar_url":"https://avatars.githubusercontent.com/u/7"}"#
        let user = try JSONDecoder().decode(GitHubClient.User.self, from: Data(json.utf8))
        #expect(user.avatarURL == "https://avatars.githubusercontent.com/u/7")
        #expect(user.noreplyEmail == "7+wes@users.noreply.github.com")
    }
}
