import AppKit
import SwiftUI

/// The app's light/dark setting.
enum AppAppearance: String, CaseIterable, Identifiable {
    case auto, light, dark

    var id: String { rawValue }
    static let storageKey = "appAppearance"

    var title: String {
        switch self {
        case .auto: "Auto"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Applies the setting to every window in the app.
    @MainActor func apply() {
        switch self {
        case .auto: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    static var saved: AppAppearance {
        AppAppearance(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .auto
    }
}

/// Links and version details for CardStock itself.
enum AppInfo {
    static let repoURL = URL(string: "https://github.com/wesvasher/CardStock")!
    static let releasesURL = URL(string: "https://github.com/wesvasher/CardStock/releases")!
    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/wesvasher/CardStock/releases/latest")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    /// True when `a` is a newer version than `b` ("1.10.0" > "1.9.2").
    static func isNewer(_ a: String, than b: String) -> Bool {
        let clean = { (v: String) in
            v.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                .split(separator: ".").map { Int($0) ?? 0 }
        }
        var x = clean(a), y = clean(b)
        let count = max(x.count, y.count)
        x += Array(repeating: 0, count: count - x.count)
        y += Array(repeating: 0, count: count - y.count)
        return x.lexicographicallyPrecedes(y) == false && x != y
    }
}

/// CardStock → Settings…: a sidebar with General (version and updates,
/// shown first), Appearance and GitHub accounts.
struct AppSettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.auto

    private enum UpdateCheck: Equatable {
        case idle, checking
        case upToDate
        case available(String, URL)
        case noReleases
        case failed(String)
    }

    @State private var update = UpdateCheck.idle
    @State private var isAddingAccount = false
    @State private var accountToRemove: GitHubAccount?

    /// The sections in the Settings sidebar.
    enum Pane: String, CaseIterable, Identifiable {
        case general, appearance, github
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: "General"
            case .appearance: "Appearance"
            case .github: "GitHub"
            }
        }

        var icon: String {
            switch self {
            case .general: "gearshape"
            case .appearance: "circle.lefthalf.filled"
            case .github: "person.crop.circle"
            }
        }
    }

    @State private var pane: Pane? = .general

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { pane in
                Label(pane.title, systemImage: pane.icon)
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(180)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch pane ?? .general {
                case .general: generalPane
                case .appearance: appearancePane
                case .github: githubPane
                }
            }
            .formStyle(.grouped)
            .navigationTitle((pane ?? .general).title)
        }
        .frame(width: 720, height: 540)
        // Open on General every time.
        .onDisappear { pane = .general }
        .onChange(of: appearance) { _, new in new.apply() }
        .sheet(isPresented: $isAddingAccount) {
            AddAccountSheet()
                .environment(model)
        }
        .confirmationDialog("Sign out of \(accountToRemove?.login ?? "this account")?",
                            isPresented: Binding(get: { accountToRemove != nil },
                                                 set: { if !$0 { accountToRemove = nil } }),
                            presenting: accountToRemove) { account in
            Button("Sign Out", role: .destructive) { model.signOut(account.login) }
        } message: { _ in
            Text("This removes the token from this Mac. Sites that publish with this account stop publishing from this Mac until you sign in again. Nothing changes on GitHub.")
        }
    }

    // MARK: - Panes

    /// Version and how to update. Shown when Settings opens.
    private var generalPane: some View {
        Form {
        Section {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text("CardStock")
                        .font(.title2.bold())
                    Text("Version \(AppInfo.version) (\(AppInfo.build))")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Link("CardStock on GitHub", destination: AppInfo.repoURL)
                }
            }
            .padding(.vertical, 4)
        }

        Section("Updates") {
            Text("CardStock doesn't update itself. To get a new version:")
            VStack(alignment: .leading, spacing: 6) {
                Text("1. Open the Releases page on GitHub and download the latest **CardStock-x.y.z.dmg**.")
                Text("2. Quit CardStock.")
                Text("3. Open the .dmg and drag CardStock into Applications. Choose **Replace** when asked.")
                Text("4. Open CardStock. If macOS says it can't check the app, go to System Settings → Privacy & Security and click **Open Anyway**.")
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            Text("Your sites, templates and GitHub sign-in are kept when you update.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Check for a New Version") { Task { await checkForUpdate() } }
                    .disabled(update == .checking)
                Link("Open Releases Page", destination: AppInfo.releasesURL)
                Spacer()
            }
            updateResult
        }
        }
    }

    private var appearancePane: some View {
        Form {
        Section("Appearance") {
            // The same tiles as the Theming page, for CardStock's own windows.
            AppearanceCards(
                selection: Binding(
                    get: { ThemeSettings.Appearance(rawValue: appearance.rawValue) ?? .auto },
                    set: { appearance = AppAppearance(rawValue: $0.rawValue) ?? .auto }),
                helpText: [.auto: "Match your Mac's setting",
                           .light: "Always use light windows",
                           .dark: "Always use dark windows"])
            Text("Auto follows your Mac's setting. This changes CardStock's windows; your website's look is set in each site's Configuration.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        }
    }

    private var githubPane: some View {
        Form {
        Section {
            if model.accounts.isEmpty {
                Text("No GitHub accounts on this Mac yet. Add one to publish sites or open them from GitHub.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.accounts) { account in
                AccountRow(account: account,
                           isDefault: account.login == model.defaultAccount?.login,
                           showsDefault: model.accounts.count > 1,
                           makeDefault: { model.defaultAccountLogin = account.login },
                           remove: { accountToRemove = account })
            }
            HStack {
                Button("Add Account…") { isAddingAccount = true }
                Spacer()
            }
        } header: {
            Text("GitHub Accounts")
        } footer: {
            Text("Tokens are kept in this Mac's Keychain. Each site remembers which account publishes it from this Mac; change it on the site's Publishing page. The default account is used for new sites and Open from GitHub.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        }
    }

    @ViewBuilder
    private var updateResult: some View {
        switch update {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking GitHub…").foregroundStyle(.secondary)
            }
        case .upToDate:
            Label("You have the latest version.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .available(let version, let url):
            HStack {
                Label("Version \(version) is available.", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
                Spacer()
                Link("Download", destination: url)
            }
        case .noReleases:
            Text("No versions have been released on GitHub yet.")
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }

    private func checkForUpdate() async {
        update = .checking
        var request = URLRequest(url: AppInfo.latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("CardStock", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 { update = .noReleases; return }
            guard status == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String
            else {
                update = .failed("GitHub didn't answer as expected. Try the Releases page.")
                return
            }
            let page = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? AppInfo.releasesURL
            let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            update = AppInfo.isNewer(latest, than: AppInfo.version) ? .available(latest, page) : .upToDate
        } catch {
            update = .failed("Couldn't reach GitHub. Check your internet connection.")
        }
    }
}

/// A GitHub account in Settings: picture, name and login, with Make Default
/// and Sign Out.
private struct AccountRow: View {
    let account: GitHubAccount
    let isDefault: Bool
    let showsDefault: Bool
    let makeDefault: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            avatar
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(account.user?.name?.isEmpty == false ? account.user!.name! : account.login)
                        .font(.headline)
                    if isDefault && showsDefault {
                        Text("Default")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }
                }
                Text(account.login)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if showsDefault && !isDefault {
                Button("Make Default", action: makeDefault)
            }
            Button("Sign Out…", action: remove)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var avatar: some View {
        let placeholder = Image(systemName: "person.crop.circle.fill")
            .resizable()
            .foregroundStyle(.secondary)
        Group {
            if let url = account.user?.avatarURL.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { image in
                    image.resizable()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
    }
}

/// Settings → Add Account…
private struct AddAccountSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add a GitHub Account")
                .font(.title2.bold())
            GitHubSignInForm(intro: "Use a token from the GitHub account you want to add. To add someone else's account, make the token while signed in to GitHub as them.") { _ in
                dismiss()
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
