import Foundation

/// The few GitHub REST calls CardStock needs.
struct GitHubClient: Sendable {
    let token: String

    struct User: Decodable, Sendable {
        var login: String
        var id: Int
        var name: String?
        var avatarURL: String?

        enum CodingKeys: String, CodingKey {
            case login, id, name
            case avatarURL = "avatar_url"
        }

        /// GitHub's private commit email, so the user's real address never
        /// lands in commit history.
        var noreplyEmail: String { "\(id)+\(login)@users.noreply.github.com" }
    }

    struct Repo: Decodable, Sendable {
        var fullName: String
        var isPrivate: Bool
        var defaultBranch: String?
        /// Size GitHub counts for the repository, in kilobytes. Updated by
        /// GitHub periodically, so it can lag behind a publish.
        var size: Int?
        var description: String?
        /// When something was last pushed, as ISO 8601 text.
        var pushedAt: String?

        enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
            case isPrivate = "private"
            case defaultBranch = "default_branch"
            case size, description
            case pushedAt = "pushed_at"
        }
    }

    /// What GitHub's status page (githubstatus.com) reports, such as "Minor
    /// Service Outage", or nil when all is well or it can't be reached.
    static func serviceStatus() async -> String? {
        struct Summary: Decodable {
            struct Status: Decodable { var indicator: String; var description: String }
            var status: Status
        }
        var req = URLRequest(url: URL(string: "https://www.githubstatus.com/api/v2/status.json")!)
        req.timeoutInterval = 5
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let summary = try? JSONDecoder().decode(Summary.self, from: data),
              summary.status.indicator != "none" else { return nil }
        return summary.status.description
    }

    func currentUser() async throws -> User {
        try await request("GET", "/user")
    }

    /// Every repository the token can reach, most recently pushed first.
    func myRepos() async throws -> [Repo] {
        var all: [Repo] = []
        for page in 1...10 {
            let batch: [Repo] = try await request("GET", "/user/repos?per_page=100&sort=pushed&page=\(page)")
            all += batch
            if batch.count < 100 { break }
        }
        return all
    }

    /// Whether a repository holds a CardStock site (a site.json at its top level).
    func hasSite(_ fullName: String) async -> Bool {
        struct Entry: Decodable { var name: String }
        guard let entries: [Entry] = try? await request("GET", "/repos/\(fullName)/contents/") else { return false }
        return entries.contains { $0.name == Site.configFile }
    }

    func repo(_ fullName: String) async throws -> Repo {
        do {
            return try await request("GET", "/repos/\(fullName)")
        } catch let error as APIError where error.status == 404 {
            let (login, scopes) = await tokenDetails()
            throw SiteError(Self.notFoundAdvice(repo: fullName, login: login, token: token, scopes: scopes))
        }
    }

    /// The token's account and, for classic tokens, its scopes (GitHub sends
    /// them in the X-OAuth-Scopes header; fine-grained tokens have none).
    private func tokenDetails() async -> (login: String?, scopes: [String]?) {
        var req = URLRequest(url: URL(string: "https://api.github.com/user")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("CardStock", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return (nil, nil) }
        let login = (try? JSONDecoder().decode(User.self, from: data))?.login
        let scopes = http.value(forHTTPHeaderField: "X-OAuth-Scopes")?
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return (login, scopes)
    }

    /// What to do when GitHub says a repository doesn't exist. GitHub says
    /// that about private repositories the token can't see, so this explains
    /// which part of the token to change.
    static func notFoundAdvice(repo: String, login: String?, token: String, scopes: [String]?) -> String {
        let start = "GitHub says \(repo) doesn't exist"
        guard let login else {
            return "\(start), or your token can't see it."
        }
        let owner = repo.split(separator: "/").first.map(String.init) ?? ""
        let someoneElses = !owner.isEmpty && owner.lowercased() != login.lowercased()
        let elsewhere = someoneElses
            ? " It belongs to \(owner), not \(login): \(owner) needs to add \(login) as a collaborator, or sign in to CardStock as \(owner)."
            : ""

        if token.hasPrefix("github_pat_") {
            return """
                \(start) for the fine-grained token you signed in with as \(login). GitHub answers that way when \
                the token can't see a private repository.

                On GitHub, open Settings → Developer settings → Fine-grained tokens and edit the token: set \
                Resource owner to \(someoneElses ? owner : login), set Repository access to All repositories \
                (or select \(repo)), and under Repository permissions set Contents to Read and write. Or make \
                a classic token with “repo” checked (Open GitHub Token Page… on the Publishing page) and sign \
                in with that.\(elsewhere)
                """
        }
        if let scopes, !scopes.contains("repo") {
            return """
                \(start) for the token you signed in with as \(login). That token can only see public \
                repositories, because “repo” wasn't checked when it was made, and \(repo) is private.

                Make a new token with “repo” checked (Open GitHub Token Page… does that for you), then sign \
                in again with it in CardStock → Settings → GitHub.\(elsewhere)
                """
        }
        return """
            \(start), signed in as \(login). Check the spelling: it's owner/name, as in the repository's \
            address on GitHub.\(elsewhere)
            """
    }

    /// True when the repo has no commits yet.
    func isEmpty(_ fullName: String) async throws -> Bool {
        do {
            let _: [EmptyResponse] = try await request("GET", "/repos/\(fullName)/commits?per_page=1")
            return false
        } catch let error as APIError where error.status == 409 {
            return true
        }
    }

    func createRepo(name: String, isPrivate: Bool, description: String) async throws -> Repo {
        let body: [String: Any] = ["name": name, "private": isPrivate, "description": description]
        do {
            return try await request("POST", "/user/repos", body: body)
        } catch let error as APIError where error.status == 422 {
            throw SiteError("Your GitHub account already has a repository named “\(name)”. Pick another name, or link the existing one.")
        }
    }

    /// A host's build of one commit, from GitHub's checks (Cloudflare
    /// Workers and Pages report there) or commit statuses (Netlify, Vercel
    /// and others).
    struct BuildCheck: Sendable, Equatable {
        var name: String
        /// Still building.
        var isRunning: Bool
        var succeeded: Bool
        /// "failure", "cancelled", "timed_out" and so on, for the log.
        var conclusion: String
        var link: String?
        var summary: String?
    }

    /// The builds GitHub knows about for a commit. Empty when there are none
    /// (or the token can't read them).
    func buildChecks(_ fullName: String, commit sha: String) async throws -> [BuildCheck] {
        struct Runs: Decodable {
            struct Run: Decodable {
                struct Output: Decodable { var title: String?; var summary: String? }
                var name: String
                var status: String
                var conclusion: String?
                var details_url: String?
                var output: Output?
            }
            var check_runs: [Run]
        }
        struct Status: Decodable {
            var context: String
            var state: String
            var target_url: String?
            var description: String?
        }
        var checks: [BuildCheck] = []
        if let runs: Runs = try? await request("GET", "/repos/\(fullName)/commits/\(sha)/check-runs") {
            checks += runs.check_runs.map { run in
                let conclusion = run.conclusion ?? run.status
                return BuildCheck(name: run.name, isRunning: run.status != "completed",
                                  succeeded: ["success", "neutral", "skipped"].contains(conclusion),
                                  conclusion: conclusion, link: run.details_url,
                                  summary: run.output?.title.flatMap { $0 == run.name ? nil : $0 })
            }
        }
        if let statuses: [Status] = try? await request("GET", "/repos/\(fullName)/commits/\(sha)/statuses") {
            // Newest first; keep the latest per context.
            var seen = Set<String>()
            for status in statuses where seen.insert(status.context).inserted {
                checks.append(BuildCheck(name: status.context, isRunning: status.state == "pending",
                                         succeeded: status.state == "success", conclusion: status.state,
                                         link: status.target_url, summary: status.description))
            }
        }
        return checks
    }

    // MARK: - Plumbing

    private struct EmptyResponse: Decodable {}

    struct APIError: LocalizedError {
        var status: Int
        var message: String
        var errorDescription: String? {
            switch status {
            case 401: "GitHub didn't accept the token. It may have expired or been revoked."
            case 403: "GitHub refused the request. The token may be missing the “repo” permission. (\(message))"
            default: "GitHub error \(status): \(message)"
            }
        }
    }

    private func request<T: Decodable>(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> T {
        var req = URLRequest(url: URL(string: "https://api.github.com" + path)!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("CardStock", forHTTPHeaderField: "User-Agent")
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw SiteError("Couldn't reach GitHub: \(error.localizedDescription)")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            throw APIError(status: status, message: message ?? "no details")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
