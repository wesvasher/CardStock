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

    /// A bare repo standing in for GitHub, with one commit holding a README.
    private func remoteWithReadme() async throws -> (remote: URL, readmeCommit: String) {
        let remote = base.appending(path: "remote.git")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try await Git(root: base).run("init", "-q", "--bare", "-b", "main", remote.path)
        let other = base.appending(path: "other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let git = Git(root: other)
        try await git.run("init", "-q", "-b", "main")
        try await git.run("config", "user.name", "Test")
        try await git.run("config", "user.email", "test@example.com")
        try "# Old site".write(to: other.appending(path: "README.md"), atomically: true, encoding: .utf8)
        try await git.run("add", "-A")
        try await git.run("commit", "-q", "-m", "Old")
        try await git.run("push", "-q", remote.path, "main")
        return (remote, try await git.run("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Linking to a repo with other files is refused unless replacing, which
    /// swaps in the site's files on top of GitHub's history (no force push).
    @Test(arguments: [true, false])
    func replacesARepoWithOtherFiles(folderHasHistory: Bool) async throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let (remote, readmeCommit) = try await remoteWithReadme()

        let a = base.appending(path: "a")
        try StarterSite.create(at: a, title: "Replace")
        let gitA = Git(root: a)
        if folderHasHistory {
            try await gitA.run("init", "-q", "-b", "main")
            try await gitA.run("config", "user.name", "Test")
            try await gitA.run("config", "user.email", "test@example.com")
            try await gitA.run("add", "-A")
            try await gitA.run("commit", "-q", "-m", "Local work")
        }
        var publisher = Publisher(root: a, token: "")
        publisher.remoteOverride = remote.path
        #expect(try await publisher.contents(of: link) == .otherFiles)

        // Refused: nothing changes, here or on the remote.
        await #expect(throws: SiteError.self) {
            _ = try await publisher.link(repo: link.repo, branch: "main", user: user)
        }
        #expect(ProjectSettings.load(from: a).github == nil)
        #expect(try await Git(root: remote).run("rev-parse", "main").hasPrefix(readmeCommit))

        _ = try await publisher.link(repo: link.repo, branch: "main", user: user, replacing: true)
        #expect(ProjectSettings.load(from: a).github == link)
        let pushed = try await Git(root: remote).run("rev-parse", "main")
        #expect(try await gitA.run("rev-parse", "HEAD") == pushed)
        let files = try await Git(root: remote).run("ls-tree", "-r", "--name-only", "main")
            .split(separator: "\n").map(String.init)
        #expect(!files.contains("README.md"))
        #expect(files.contains(Site.configFile))
        #expect(files.contains("public/index.html"))
        // The old files are still in the history.
        _ = try await Git(root: remote).run("merge-base", "--is-ancestor", readmeCommit, "main")
        if folderHasHistory {
            #expect(try await gitA.run("log", "--format=%s").contains("Local work"))
        }
        #expect(try await gitA.run("status", "--porcelain").isEmpty)

        // Publishing afterwards works as usual.
        try setSummary(a, "pages/hello-world.md", "After replacing")
        let outcome = try await publisher.publish(link: link, user: user, message: "")
        #expect(outcome.committed && !outcome.pulledChanges)
    }

    /// A copy of the site with its history (from another Mac) links to the
    /// repo it came from, and picks up what was published there since.
    @Test func linksACopyWithTheSameHistory() async throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let remote = base.appending(path: "remote.git")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try await Git(root: base).run("init", "-q", "--bare", "-b", "main", remote.path)

        let a = base.appending(path: "a")
        try StarterSite.create(at: a, title: "Same")
        let gitA = Git(root: a)
        try await gitA.run("init", "-q", "-b", "main")
        try await gitA.run("remote", "add", "origin", remote.path)
        _ = try await Publisher(root: a, token: "").publish(link: link, user: user, message: "First")

        // The copy: same history, never linked, with its own edit.
        let copy = base.appending(path: "copy")
        try FileManager.default.copyItem(at: a, to: copy)
        try await Git(root: copy).run("remote", "remove", "origin")
        try setSummary(copy, "pages/hello-world.md", "Edited in the copy")

        // Meanwhile the original publishes another page.
        try "---\ntitle: New\n---\nNew".write(to: a.appending(path: "pages/new.md"), atomically: true, encoding: .utf8)
        _ = try await Publisher(root: a, token: "").publish(link: link, user: user, message: "")

        var publisher = Publisher(root: copy, token: "")
        publisher.remoteOverride = remote.path
        #expect(try await publisher.contents(of: link) == .sameSite)
        _ = try await publisher.link(repo: link.repo, branch: "main", user: user)
        #expect(FileManager.default.fileExists(atPath: copy.appending(path: "pages/new.md").path))
        let pushed = try await Git(root: remote).run("rev-parse", "main")
        #expect(try await Git(root: copy).run("rev-parse", "HEAD") == pushed)
        let home = try await Git(root: remote).run("show", "main:public/index.html")
        #expect(home.contains("Edited in the copy"))
    }

    @Test func anEmptyRepoIsEmpty() async throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let remote = base.appending(path: "remote.git")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try await Git(root: base).run("init", "-q", "--bare", "-b", "main", remote.path)
        let a = base.appending(path: "a")
        try StarterSite.create(at: a, title: "Empty")
        var publisher = Publisher(root: a, token: "")
        publisher.remoteOverride = remote.path
        #expect(try await publisher.contents(of: link) == .empty)
        _ = try await publisher.link(repo: link.repo, user: user)
        #expect(try await Git(root: a).run("rev-parse", "HEAD") == (try await Git(root: remote).run("rev-parse", "main")))
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

    @Test func explainsWhyARepoIsntFound() {
        let repo = "wes/site"
        let narrow = GitHubClient.notFoundAdvice(repo: repo, login: "wes", token: "ghp_x", scopes: ["public_repo"])
        #expect(narrow.contains("only see public"))
        let fine = GitHubClient.notFoundAdvice(repo: repo, login: "wes", token: "github_pat_x", scopes: nil)
        #expect(fine.contains("Contents to Read and write"))
        let typo = GitHubClient.notFoundAdvice(repo: repo, login: "wes", token: "ghp_x", scopes: ["repo"])
        #expect(typo.contains("spelling"))
        #expect(!typo.contains("collaborator"))
        let theirs = GitHubClient.notFoundAdvice(repo: "jane/blog", login: "wes", token: "ghp_x", scopes: ["repo"])
        #expect(theirs.contains("collaborator"))
        #expect(GitHubClient.notFoundAdvice(repo: repo, login: nil, token: "", scopes: nil).contains("can't see it"))
    }

    @Test func readsTheAvatarFromGitHub() throws {
        let json = #"{"login":"wes","id":7,"name":"Wes","avatar_url":"https://avatars.githubusercontent.com/u/7"}"#
        let user = try JSONDecoder().decode(GitHubClient.User.self, from: Data(json.utf8))
        #expect(user.avatarURL == "https://avatars.githubusercontent.com/u/7")
        #expect(user.noreplyEmail == "7+wes@users.noreply.github.com")
    }
}

struct GitErrorTests {
    /// The push error GitHub gave during an outage (November 2026).
    let outage = """
        remote: Internal Server Error
        remote: Request ID C5BB:1D65FA:22615BD:2DCD4C7:6AEB0804
        To https://github.com/wes/site.git
         ! [remote rejected] HEAD -> main (Internal Server Error)
        error: failed to push some refs to 'https://github.com/wes/site.git'
        """

    @Test func spotsGitHubTroubleAndBeingOffline() {
        #expect(Git.networkProblem(in: outage) == .gitHubTrouble)
        #expect(Git.networkProblem(in: "error: RPC failed; HTTP 503 curl 22 The requested URL returned error: 503") == .gitHubTrouble)
        #expect(Git.networkProblem(in: "fatal: unable to access 'https://github.com/a/b.git/': Could not resolve host: github.com") == .offline)
        #expect(Git.networkProblem(in: "! [rejected] main -> main (fetch first)") == nil)
        #expect(Git.networkProblem(in: "remote: Invalid username or token.") == nil)
    }

    @Test func explainsInPlainWords() {
        let push = Git.Failure(command: "push", message: outage)
        #expect(push.problem == .gitHubTrouble)
        #expect(push.localizedDescription.hasPrefix("GitHub had a problem on its side and didn't take your changes"))
        #expect(push.rawDescription.contains("Request ID"))
        #expect(Git.Failure(command: "fetch", message: outage).localizedDescription.contains("couldn't send the latest"))
        // Only commands that talk to GitHub; others keep git's words.
        let local = Git.Failure(command: "commit", message: "Internal Server Error")
        #expect(local.problem == nil)
        #expect(local.localizedDescription == "git commit failed: Internal Server Error")
    }
}
