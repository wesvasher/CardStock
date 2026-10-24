import Foundation

/// `.cardstock-local/` in a site folder: data that belongs to this Mac only
/// (such as a scheduled publish). Kept out of git.
enum LocalData {
    static let folderName = ".cardstock-local"

    static func folder(in root: URL) -> URL { root.appending(path: folderName, directoryHint: .isDirectory) }

    private static let accountFile = "github-account"

    /// The GitHub account this Mac publishes the site with, when one was
    /// chosen. Kept per Mac: two people can publish one site from their own
    /// accounts, and no username is committed.
    static func gitHubAccount(in root: URL) -> String? {
        let url = folder(in: root).appending(path: accountFile)
        let text = (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    static func setGitHubAccount(_ login: String?, in root: URL) {
        let url = folder(in: root).appending(path: accountFile)
        guard let login else { try? FileManager.default.removeItem(at: url); return }
        prepare(in: root)
        try? FileManager.default.createDirectory(at: folder(in: root), withIntermediateDirectories: true)
        try? (login + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// Makes sure the site's .gitignore keeps this folder out of git, and
    /// removes files from features CardStock no longer has.
    static func prepare(in root: URL) {
        let url = root.appending(path: ".gitignore")
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let lines = Set(existing.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) })
        if !lines.contains(folderName) && !lines.contains("\(folderName)/") && !lines.contains("/\(folderName)/") {
            var text = existing
            if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
            text += "\(folderName)/\n"
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
        // The old image record (from when removed images went to a Trash folder).
        try? FileManager.default.removeItem(at: folder(in: root).appending(path: "media.json"))
    }
}
