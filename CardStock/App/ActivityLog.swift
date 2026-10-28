import Foundation
import Observation

/// One thing that happened in CardStock.
struct LogEntry: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        /// Opening and closing sites, accounts, app-wide settings.
        case app
        /// Changes to pages, files, settings and styles.
        case edit
        /// Building, publishing, linking and syncing with GitHub.
        case publish
        /// The host's build after a publish (Cloudflare and others).
        case hosting
        /// Something that went wrong.
        case error

        var title: String {
            switch self {
            case .app: "App"
            case .edit: "Edit"
            case .publish: "Publishing"
            case .hosting: "Hosting"
            case .error: "Error"
            }
        }

        var systemImage: String {
            switch self {
            case .app: "macwindow"
            case .edit: "pencil"
            case .publish: "arrow.up.circle"
            case .hosting: "cloud"
            case .error: "exclamationmark.triangle.fill"
            }
        }
    }

    var id = UUID()
    var date = Date.now
    var kind: Kind
    /// The site's title, or nil for app-wide events.
    var site: String?
    /// The site's folder, to show only that site's entries.
    var sitePath: String?
    var message: String
    var detail: String?
    /// A web address with more, such as a build log.
    var link: String?
    /// Marks events that should only be logged once (a commit's build).
    var key: String?
    /// For hosting events: the build failed.
    var failed = false

    var isProblem: Bool { kind == .error || failed }

    /// One line of the exported text file.
    var exportLine: String {
        var line = "\(Self.exportDate.string(from: date))  \(kind.title.padding(toLength: 10, withPad: " ", startingAt: 0))"
        if let site { line += "  [\(site)]" }
        line += "  \(message)"
        if let detail, !detail.isEmpty { line += "\n    " + detail.replacingOccurrences(of: "\n", with: "\n    ") }
        if let link { line += "\n    " + link }
        return line
    }

    private static let exportDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
}

/// Everything that happens in CardStock, newest last, for Status → Activity
/// Log. Kept for all sites in one file in Application Support (JSON Lines,
/// one entry per line), so it survives quitting; only the newest entries
/// are kept.
@MainActor
@Observable
final class ActivityLog {
    private(set) var entries: [LogEntry] = []
    /// nil keeps the log in memory only (tests).
    private let fileURL: URL?
    static let limit = 5000

    static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "CardStock/activity-log.jsonl")
    }

    init(fileURL: URL?) {
        self.fileURL = fileURL
        guard let fileURL, let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        let decoder = JSONDecoder()
        entries = text.split(separator: "\n").compactMap { try? decoder.decode(LogEntry.self, from: Data($0.utf8)) }
        if entries.count > Self.limit { trimAndRewrite() }
    }

    func add(_ entry: LogEntry) {
        if let key = entry.key, entries.contains(where: { $0.key == key }) { return }
        entries.append(entry)
        if entries.count > Self.limit + 500 {
            trimAndRewrite()
        } else {
            append(entry)
        }
    }

    func contains(key: String) -> Bool { entries.contains { $0.key == key } }

    /// Deletes every entry, or only those of one site (by folder).
    func clear(sitePath: String? = nil) {
        if let sitePath {
            entries.removeAll { $0.sitePath == sitePath }
        } else {
            entries.removeAll()
        }
        rewrite()
    }

    /// The entries as a plain text file, oldest first.
    static func exportText(_ entries: [LogEntry]) -> String {
        "CardStock Activity Log\n\n" + entries.map(\.exportLine).joined(separator: "\n") + "\n"
    }

    private func append(_ entry: LogEntry) {
        guard let fileURL, let data = try? JSONEncoder().encode(entry) else { return }
        let line = data + Data("\n".utf8)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? line.write(to: fileURL)
        }
    }

    private func trimAndRewrite() {
        entries = Array(entries.suffix(Self.limit))
        rewrite()
    }

    private func rewrite() {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        let text = entries.compactMap { try? encoder.encode($0) }.map { String(decoding: $0, as: UTF8.self) }
            .joined(separator: "\n")
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? (text.isEmpty ? "" : text + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
