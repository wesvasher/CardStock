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
            throw SiteError("Couldn't find \(fullName) on GitHub, or your token doesn't have access to it.")
        }
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
