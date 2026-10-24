import SwiftUI

/// Signing in to GitHub and linking this site to a repository.
struct GitHubSetupSection: View {
    @Environment(AppModel.self) private var model
    let site: Site

    @State private var showExisting = false
    @State private var newRepoName = ""
    @State private var isPrivate = true
    @State private var existingRepo = ""
    @State private var linkAccount = ""
    @State private var confirmUnlink = false

    var body: some View {
        Section {
            if !model.gitAvailable {
                gitMissing
            } else if let link = model.project.github {
                linked(link)
                if model.hasAccounts {
                    siteAccountRow
                }
                if !model.isSignedIn {
                    if let missing = model.missingSiteAccount {
                        signInFields(intro: "This Mac publishes \(link.repo) as \(missing), which isn't signed in any more. Sign in as \(missing), or choose another account above.")
                    } else {
                        signInFields(intro: "This site is linked to \(link.repo). Sign in to GitHub to publish from this Mac.")
                    }
                }
            } else if !model.hasAccounts {
                signInFields(intro: "Optional. Linking to GitHub keeps a copy of your site online, syncs it between your Macs, and lets Cloudflare Pages host it. Without it, CardStock works entirely on this Mac. Sign in first; then one click creates a repository for this site.")
            } else {
                linkFields
            }
        } header: {
            Text(model.project.github == nil ? "Set Up GitHub Publishing" : "GitHub")
        } footer: {
            if model.hasAccounts {
                HStack {
                    Text("Add or remove GitHub accounts in CardStock's Settings.")
                        .foregroundStyle(.secondary)
                    SettingsLink { Text("Manage Accounts…") }
                        .buttonStyle(.link)
                }
                .font(.caption)
            }
        }
        .disabled(model.isWorking)
        .onAppear {
            if newRepoName.isEmpty { newRepoName = Site.slugify(site.config.title) }
            if linkAccount.isEmpty { linkAccount = model.defaultAccount?.login ?? "" }
        }
        .onChange(of: model.accounts) {
            if !model.accounts.contains(where: { $0.login == linkAccount }) {
                linkAccount = model.defaultAccount?.login ?? ""
            }
        }
        .confirmationDialog("Unlink this site from GitHub?", isPresented: $confirmUnlink) {
            Button("Unlink", role: .destructive) { Task { await model.unlink() } }
        } message: {
            Text("The site stays on this Mac with its history, and the repository stays on GitHub. CardStock just stops publishing to it.")
        }
    }

    /// Which account publishes this site from this Mac.
    @ViewBuilder
    private var siteAccountRow: some View {
        let missing = model.missingSiteAccount
        if model.accounts.count == 1 && missing == nil, let only = model.accounts.first {
            LabeledContent("Publishing as") {
                Text(only.displayName)
            }
        } else {
            Picker("Publishing as", selection: Binding(
                get: { model.siteAccount?.login ?? missing ?? "" },
                set: { model.setSiteAccount($0) })) {
                ForEach(model.accounts) { account in
                    Text(account.displayName).tag(account.login)
                }
                if let missing {
                    Text("\(missing) (not signed in)").tag(missing)
                }
            }
        }
    }

    private var gitMissing: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Publishing to GitHub needs Apple's Command Line Tools, which include git. Installing them takes a few minutes.")
            HStack {
                Button("Install Command Line Tools") { Git.installCommandLineTools() }
                Button("Check Again") { Task { await model.recheckGit() } }
            }
        }
    }

    /// For a linked site, the account signed in here is the one it publishes with.
    private func signInFields(intro: String) -> some View {
        GitHubSignInForm(intro: intro) { login in
            if model.project.github != nil { model.setSiteAccount(login) }
        }
        .padding(.vertical, 4)
    }

    /// For a site that isn't on GitHub yet. Creating a new repository is the
    /// main path (one click creates it, links it and uploads the site);
    /// linking an existing empty one is tucked underneath.
    private var linkFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "plus.rectangle.on.folder.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Starting from scratch? Create a repository for this site")
                            .font(.headline)
                        Text("One click creates a new repository on GitHub, links it to this site and uploads everything. After that, Publish sends your changes.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                accountRow

                VStack(alignment: .leading, spacing: 4) {
                    TextField("Repository name", text: $newRepoName, prompt: Text("my-site"))
                    if let login = selectedLinkLogin, !Site.slugify(newRepoName).isEmpty {
                        Text("Will be created as github.com/\(login)/\(Site.slugify(newRepoName))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Private repository", isOn: $isPrivate)
                    Text(isPrivate
                         ? "Recommended. Your published website is still public; the repository holds your drafts, which stay private."
                         : "Anyone can see a public repository on GitHub, including drafts.")
                        .font(.caption)
                        .foregroundStyle(isPrivate ? Color.secondary : Color.orange)
                }

                Button {
                    let name = Site.slugify(newRepoName)
                    let account = linkAccount
                    Task { await model.linkNewRepo(name: name, isPrivate: isPrivate, account: account) }
                } label: {
                    Label("Create Repository and Link", systemImage: "plus.circle.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(Site.slugify(newRepoName).isEmpty)
            }
            .padding(14)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

            DisclosureGroup("Already made an empty repository on GitHub? Link it instead", isExpanded: $showExisting) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Repository", text: $existingRepo, prompt: Text("owner/name"))
                    Text("The repository must be empty: no README or other files.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Link Existing Repository") {
                        let repo = existingRepo
                        let account = linkAccount
                        Task { await model.linkExistingRepo(repo, account: account) }
                    }
                    .disabled(!existingRepo.contains("/"))
                }
                .padding(.top, 6)
            }
        }
        .padding(.vertical, 4)
    }

    private var selectedLinkLogin: String? {
        model.accounts.first { $0.login == linkAccount }?.login ?? model.defaultAccount?.login
    }

    /// Whose GitHub account the new repository goes in.
    @ViewBuilder
    private var accountRow: some View {
        if model.accounts.count > 1 {
            Picker("GitHub account", selection: $linkAccount) {
                ForEach(model.accounts) { account in
                    Text(account.displayName).tag(account.login)
                }
            }
        } else if let only = model.accounts.first {
            LabeledContent("GitHub account", value: only.displayName)
        }
    }

    private func linked(_ link: ProjectSettings.GitHubLink) -> some View {
        Group {
            LabeledContent("Repository") {
                Link(link.repo, destination: link.webURL)
            }
            LabeledContent("Branch", value: link.branch)
            HStack {
                Button("Open on GitHub") { NSWorkspace.shared.open(link.webURL) }
                Spacer()
                Button("Unlink…", role: .destructive) { confirmUnlink = true }
            }
        }
    }
}
