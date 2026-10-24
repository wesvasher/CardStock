import AppKit
import SwiftUI

/// Downloads a site from GitHub and opens it: sign in if needed, pick one
/// of your repositories that holds a CardStock site, choose where to keep it.
struct OpenFromGitHubSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var repos: [GitHubClient.Repo] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var selectedRepo: String?
    @State private var search = ""
    @State private var parent = SiteDownloader.defaultParent
    /// The account whose repositories are listed.
    @State private var account = ""
    @State private var isAddingAccount = false

    private var showsSignIn: Bool { !model.hasAccounts || isAddingAccount }

    /// How many recently pushed repositories are checked for a site.
    private static let checkLimit = 100

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Open from GitHub")
                    .font(.title2.bold())
                Text("Download a site you've published from another Mac, ready to edit and publish here.")
                    .foregroundStyle(.secondary)
                if model.hasAccounts && !isAddingAccount {
                    accountPicker
                        .padding(.top, 8)
                }
            }
            .padding([.horizontal, .top], 24)
            .padding(.bottom, 16)

            Group {
                if !model.gitAvailable {
                    gitMissing
                } else if showsSignIn {
                    ScrollView {
                        GitHubSignInForm(intro: model.hasAccounts
                                         ? "Sign in to another GitHub account. CardStock remembers each account on this Mac."
                                         : "Sign in to GitHub to see your sites. Each Mac signs in once; the token is used for publishing too.") { login in
                            isAddingAccount = false
                            account = login
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                    }
                } else {
                    repoPicker
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            Divider()
            footer
                .padding(16)
        }
        .frame(width: 560, height: 560)
        .onAppear {
            if account.isEmpty { account = model.defaultAccount?.login ?? "" }
        }
        .task(id: account) {
            repos = []
            selectedRepo = nil
            if !account.isEmpty { await loadRepos() }
        }
    }

    // MARK: - Repositories

    private var filtered: [GitHubClient.Repo] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return repos }
        return repos.filter {
            $0.fullName.localizedCaseInsensitiveContains(query)
                || ($0.description ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    @ViewBuilder
    private var repoPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking for sites in your repositories…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                VStack(spacing: 10) {
                    Text(loadError)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try Again") { Task { await loadRepos() } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)
            } else if repos.isEmpty {
                VStack(spacing: 6) {
                    Text("No sites found")
                        .font(.headline)
                    Text("None of your GitHub repositories has a CardStock site in it yet. Sites appear here after they're published from CardStock.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 40)
            } else {
                TextField("Search", text: $search, prompt: Text("Search your sites"))
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 24)
                List(filtered, id: \.fullName, selection: $selectedRepo) { repo in
                    RepoRow(repo: repo, isOnThisMac: isOnThisMac(repo))
                        .tag(repo.fullName)
                }
                .scrollContentBackground(.hidden)
                .contextMenu(forSelectionType: String.self) { _ in } primaryAction: { _ in
                    download()
                }
                .padding(.horizontal, 14)
            }
        }
    }

    private func isOnThisMac(_ repo: GitHubClient.Repo) -> Bool {
        let folder = parent.appending(path: SiteDownloader.folderName(for: repo.fullName))
        return Site.isSite(folder) && ProjectSettings.load(from: folder).github?.repo == repo.fullName
    }

    /// Lists the user's repositories, keeping the ones with a site in them.
    private func loadRepos() async {
        guard let token = model.token(for: account) else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let client = GitHubClient(token: token)
            let all = Array(try await client.myRepos().prefix(Self.checkLimit))
            let sites = await withTaskGroup(of: String?.self) { group in
                for repo in all {
                    group.addTask { await client.hasSite(repo.fullName) ? repo.fullName : nil }
                }
                var found: Set<String> = []
                for await name in group { if let name { found.insert(name) } }
                return found
            }
            repos = all.filter { sites.contains($0.fullName) }
            if repos.count == 1 { selectedRepo = repos[0].fullName }
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if model.isWorking, let message = model.workMessage {
                ProgressView().controlSize(.small)
                Text(message)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if !showsSignIn {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(displayPath(parent))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .help(parent.path)
                Button("Change…", action: chooseParent)
            }
            Spacer()
            if isAddingAccount && model.hasAccounts {
                Button("Back") { isAddingAccount = false }
            }
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            if !showsSignIn {
                Button("Download and Open", action: download)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedRepo == nil || model.isWorking)
            }
        }
    }

    /// Whose repositories to list, with a way to sign in to another account.
    private var accountPicker: some View {
        HStack(spacing: 8) {
            Picker("Account", selection: $account) {
                ForEach(model.accounts) { account in
                    Text(account.displayName).tag(account.login)
                }
            }
            .fixedSize()
            Button("Add Account…") { isAddingAccount = true }
                .buttonStyle(.link)
            Spacer()
        }
    }

    private var gitMissing: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Downloading a site needs Apple's Command Line Tools, which include git. Installing them takes a few minutes.")
            HStack {
                Button("Install Command Line Tools") { Git.installCommandLineTools() }
                Button("Check Again") { Task { await model.recheckGit() } }
            }
        }
        .padding(.horizontal, 24)
    }

    private func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func chooseParent() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose where to keep the site. CardStock makes a folder for it here."
        if panel.runModal() == .OK, let url = panel.url { parent = url }
    }

    private func download() {
        guard let name = selectedRepo, let repo = repos.first(where: { $0.fullName == name }) else { return }
        Task {
            if await model.downloadSite(repo, into: parent, account: account) { dismiss() }
        }
    }
}

/// One repository: name, description, private badge and when it was last
/// published.
private struct RepoRow: View {
    let repo: GitHubClient.Repo
    let isOnThisMac: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "globe")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(repo.fullName)
                        .font(.headline)
                        .lineLimit(1)
                    if repo.isPrivate {
                        Badge(text: "Private")
                    }
                    if isOnThisMac {
                        Badge(text: "On this Mac")
                    }
                }
                if let description = repo.description, !description.isEmpty {
                    Text(description)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let pushed = repo.pushedAt.flatMap({ try? Date($0, strategy: .iso8601) }) {
                    Text("Published \(pushed.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct Badge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Color.primary.opacity(0.08), in: Capsule())
    }
}
