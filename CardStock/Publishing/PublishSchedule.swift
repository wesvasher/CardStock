import Foundation

/// A publish set to happen automatically at a certain time.
///
/// Kept per Mac in the site's `.cardstock-local/scheduled-publish.json`
/// (ignored by git), since it's this Mac that publishes.
struct ScheduledPublish: Codable, Equatable, Sendable {
    var date: Date
    /// Description of the changes, used for the commit.
    var message: String
    /// Why the last attempt failed. While set, nothing happens until the
    /// user tries again or removes the schedule.
    var failure: String?

    static let fileName = "scheduled-publish.json"

    private static func url(in root: URL) -> URL {
        LocalData.folder(in: root).appending(path: fileName)
    }

    static func load(from root: URL) -> ScheduledPublish? {
        guard let data = try? Data(contentsOf: url(in: root)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ScheduledPublish.self, from: data)
    }

    /// Saves the schedule, or removes the file for nil.
    static func save(_ schedule: ScheduledPublish?, in root: URL) throws {
        let url = url(in: root)
        guard let schedule else {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            return
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(schedule).write(to: url, options: .atomic)
    }

    /// "2d 4h 13m 05s" style countdown; seconds always shown, larger units
    /// only when needed.
    static func countdown(to date: Date, from now: Date = .now) -> String {
        let total = max(0, Int(date.timeIntervalSince(now).rounded(.up)))
        let days = total / 86_400, hours = total % 86_400 / 3600
        let minutes = total % 3600 / 60, seconds = total % 60
        if days > 0 { return String(format: "%dd %dh %02dm %02ds", days, hours, minutes, seconds) }
        if hours > 0 { return String(format: "%dh %02dm %02ds", hours, minutes, seconds) }
        return String(format: "%dm %02ds", minutes, seconds)
    }
}
