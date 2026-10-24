import Foundation
import UniformTypeIdentifiers

/// A saved, named look (Theming settings) that any site can use.
struct SavedStyle: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var savedAt = Date.now
    var theme: ThemeSettings
}

/// Styles saved on this Mac, one JSON file each in
/// ~/Library/Application Support/CardStock/Styles. Styles are shared between
/// sites; using one copies it into the site's own theme/theme.json.
struct StyleLibrary: Sendable {
    let folder: URL

    static let fileExtension = "cardstockstyle"
    static let fileType = UTType(filenameExtension: fileExtension, conformingTo: .json) ?? .json
    /// Files exported before Styles were renamed from theme sets.
    static let legacyFileType = UTType(filenameExtension: "cardstocktheme", conformingTo: .json) ?? .json

    static var standard: StyleLibrary {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = support.appending(path: "CardStock/Styles")
        // Move the library from its old name, if needed.
        let legacy = support.appending(path: "CardStock/Themes")
        let fm = FileManager.default
        if !fm.fileExists(atPath: folder.path) && fm.fileExists(atPath: legacy.path) {
            try? fm.moveItem(at: legacy, to: folder)
        }
        return StyleLibrary(folder: folder)
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    func load() -> [SavedStyle] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? Self.decoder.decode(SavedStyle.self, from: Data(contentsOf: $0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func save(_ set: SavedStyle) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Self.encoder.encode(set).write(to: file(for: set.id), options: .atomic)
    }

    func delete(_ id: UUID) throws {
        let url = file(for: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func file(for id: UUID) -> URL {
        folder.appending(path: "\(id.uuidString).json")
    }

    // MARK: - Sharing

    /// The file format for exported sets.
    private struct Exported: Codable {
        var format = "cardstock-style"
        var version = 1
        var name: String
        var theme: ThemeSettings
    }

    static func exportData(_ set: SavedStyle) throws -> Data {
        try encoder.encode(Exported(name: set.name, theme: set.theme))
    }

    /// Reads an exported style (including older .cardstocktheme files). Also accepts a site's theme.json, named after the file.
    static func importSet(from url: URL) throws -> SavedStyle {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SiteError("Couldn't read “\(url.lastPathComponent)”.")
        }
        if let exported = try? decoder.decode(Exported.self, from: data), ["cardstock-style", "cardstock-theme"].contains(exported.format) {
            return SavedStyle(name: exported.name, theme: exported.theme)
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           object["light"] != nil || object["bodyFont"] != nil,
           let theme = try? decoder.decode(ThemeSettings.self, from: data) {
            var name = url.deletingPathExtension().lastPathComponent
            if name == "theme" { name = url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent }
            return SavedStyle(name: name, theme: theme)
        }
        throw SiteError("“\(url.lastPathComponent)” isn't a CardStock template.")
    }

    /// `base`, or `base 2`, `base 3`… so names don't collide.
    static func uniqueName(_ base: String, existing: [SavedStyle]) -> String {
        let names = Set(existing.map { $0.name.lowercased() })
        let trimmed = base.trimmingCharacters(in: .whitespaces)
        let start = trimmed.isEmpty ? "Untitled Theme" : trimmed
        guard names.contains(start.lowercased()) else { return start }
        var n = 2
        while names.contains("\(start) \(n)".lowercased()) { n += 1 }
        return "\(start) \(n)"
    }
}
