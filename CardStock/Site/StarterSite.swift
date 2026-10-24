import Foundation

/// Creates a new site from the starter template bundled with the app.
enum StarterSite {
    static func create(at root: URL, title: String) throws {
        let fm = FileManager.default
        guard let template = Bundle.main.url(forResource: "StarterSite", withExtension: nil) else {
            throw SiteError("The starter site is missing from the app bundle.")
        }
        if fm.fileExists(atPath: root.path) {
            let existing = try fm.contentsOfDirectory(atPath: root.path).filter { !$0.hasPrefix(".") }
            guard existing.isEmpty else {
                throw SiteError("“\(root.lastPathComponent)” already has files in it. Choose an empty folder.")
            }
        } else {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
        }

        for name in try fm.contentsOfDirectory(atPath: template.path) where !name.hasPrefix("._") {
            try fm.copyItem(at: template.appending(path: name), to: root.appending(path: name))
        }
        // Hidden files may not survive app bundling, so write them here.
        try "# CardStock\n.DS_Store\n._*\n.public-building/\n"
            .write(to: root.appending(path: ".gitignore"), atomically: true, encoding: .utf8)
        try fm.createDirectory(at: root.appending(path: "media"), withIntermediateDirectories: true)
        try Data().write(to: root.appending(path: "media/.gitkeep"))

        var site = try Site.load(from: root)
        site.config.title = title
        try site.saveConfig()
        // The double-clickable project file: "<Site Name>.cardstock".
        try ProjectSettings.ensureProjectFile(in: root)
    }
}
