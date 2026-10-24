import Foundation

/// A GitHub account signed in on this Mac. Its token is in the Keychain;
/// `user` is filled in from GitHub when it can be reached.
struct GitHubAccount: Identifiable, Equatable, Sendable {
    var login: String
    var user: GitHubClient.User?
    var id: String { login.lowercased() }

    var displayName: String {
        if let name = user?.name, !name.isEmpty { return "\(name) (\(login))" }
        return login
    }

    static func == (a: GitHubAccount, b: GitHubAccount) -> Bool {
        a.login == b.login && a.user?.id == b.user?.id && a.user?.name == b.user?.name
    }
}

/// Which account a site publishes with.
enum GitHubAccounts {
    /// The login to use for a site: the account chosen for it on this Mac
    /// (`chosen`, from `.cardstock-local/`); otherwise the account that owns
    /// the repo, then the default account. A chosen account that isn't signed
    /// in any more gets nil, so the user is asked to sign in as that account
    /// (or pick another) rather than silently publishing as someone else.
    static func login(for link: ProjectSettings.GitHubLink?, chosen: String?, signedIn logins: [String],
                      defaultLogin: String?) -> String? {
        func find(_ name: String?) -> String? {
            guard let name else { return nil }
            return logins.first { $0.caseInsensitiveCompare(name) == .orderedSame }
        }
        let fallback = find(defaultLogin) ?? logins.first
        guard let link else { return fallback }
        if let chosen { return find(chosen) }
        let owner = link.repo.split(separator: "/").first.map(String.init)
        return find(owner) ?? fallback
    }
}
