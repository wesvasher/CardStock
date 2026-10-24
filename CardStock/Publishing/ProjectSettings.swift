import Foundation

/// CardStock's own settings for a site, saved in the site's project file,
/// `<Site Name>.cardstock`, at the root of the site folder. Double-clicking
/// that file opens the site in CardStock. It travels with the folder and is
/// committed with the site, so it never holds secrets.
struct ProjectSettings: Codable, Equatable, Sendable {
    struct GitHubLink: Codable, Equatable, Sendable {
        /// `owner/name`
        var repo: String
        var branch: String

        var webURL: URL { URL(string: "https://github.com/\(repo)")! }
        var remoteURL: String { "https://github.com/\(repo).git" }
    }

    var format = "cardstock-project"
    var version = 1
    var github: GitHubLink?

    static let fileExtension = "cardstock"
    /// Where these settings lived before the project file existed.
    static let legacyFileName = "cardstock.json"

    init(github: GitHubLink? = nil) {
        self.github = github
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? format
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? version
        github = try c.decodeIfPresent(GitHubLink.self, forKey: .github)
    }

    /// The site's project file, if it has one.
    static func projectFile(in root: URL) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return files
            .filter { $0.pathExtension == fileExtension && !$0.lastPathComponent.hasPrefix("._") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first
    }

    static func load(from root: URL) -> ProjectSettings {
        let url = projectFile(in: root) ?? root.appending(path: legacyFileName)
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(ProjectSettings.self, from: data)
        else { return ProjectSettings() }
        return settings
    }

    /// Writes the project file, creating `<folder name>.cardstock` if needed.
    func save(to root: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let url = Self.projectFile(in: root) ?? Self.newProjectFileURL(in: root)
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// Makes sure the site has a project file, moving settings over from an
    /// old cardstock.json. Returns the project file.
    @discardableResult
    static func ensureProjectFile(in root: URL) throws -> URL {
        if let existing = projectFile(in: root) { return existing }
        let settings = load(from: root)
        try settings.save(to: root)
        let legacy = root.appending(path: legacyFileName)
        if FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.removeItem(at: legacy)
        }
        return projectFile(in: root) ?? newProjectFileURL(in: root)
    }

    private static func newProjectFileURL(in root: URL) -> URL {
        var name = root.lastPathComponent
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        if name.isEmpty || name.hasPrefix(".") { name = "Site" }
        return root.appending(path: "\(name).\(fileExtension)")
    }
}
