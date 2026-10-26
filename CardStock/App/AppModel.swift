import AppKit
import Foundation
import Observation
import SwiftUI

/// What's selected in the sidebar.
enum SidebarSelection: Hashable {
    case start
    /// Site health, connections and help with problems.
    case status
    case configuration
    case publish
    case pages
    case files
    case help
    case item(URL)

    /// Whether this view has a right-hand column (a preview, a file, or a
    /// help article). Start, Status, Configuration and Publishing don't.
    var hasPreviewColumn: Bool {
        switch self {
        case .pages, .files, .help, .item: true
        case .start, .status, .configuration, .publish: false
        }
    }
}

/// App state: the open site, the selection, saving, building and publishing.
@MainActor @Observable
final class AppModel {
    private(set) var site: Site?
    private(set) var project = ProjectSettings()
    var selection: SidebarSelection? {
        didSet {
            // Every page is edited inside the Pages view (list, editor,
            // preview), so opening one from anywhere goes there.
            if case .item(let id) = selection, site?.items.contains(where: { $0.id == id }) == true {
                selectedPageID = id
                selection = .pages
            }
        }
    }
    var errorMessage: String?
    var statusMessage: String?
    /// Bumped whenever content changes so the preview can refresh.
    private(set) var revision = 0 { didSet { scheduleHealthCount() } }
    /// How many problems Site Health lists, for the badge on Status in the
    /// sidebar. Counted a moment after the site or its files change, since
    /// the checks read files on disk.
    private(set) var healthProblemCount = 0
    private var healthTask: Task<Void, Never>?
    /// Everything in the site's media/ folder, for the Files page.
    private(set) var files: [MediaFile] = [] { didSet { scheduleHealthCount() } }
    /// Files selected on the Files page; the preview column shows them.
    var selectedFileIDs: Set<MediaFile.ID> = []
    /// The page selected on the Pages view; the preview column shows it.
    var selectedPageID: URL?
    /// The page shown in Configuration (Site Details, Fonts, Footer, …).
    var configPage: ConfigPage = .site
    /// The layout previewed on Configuration → Layouts (empty: Standard).
    var previewLayoutID = ""
    /// The collection shown on Configuration → Collections (and previewed).
    var configCollectionID = ""
    /// The tag previewed on Configuration → Tags (empty: the list of tags).
    var previewTagSlug = ""

    /// Configuration → Collections' preview: the chosen collection's main page.
    var previewCollectionPath: String {
        let collections = site?.config.collections ?? []
        return (collections.first { $0.id == configCollectionID } ?? ContentCollection.alphabetical(collections).first)?.mainPath
            ?? SiteRenderer.templatePagePath
    }

    /// The folder previewed on Configuration → Folders.
    var previewFolderName = ""
    var previewFolderPath: String {
        site?.config.folders.first { $0.name == previewFolderName }?.path ?? SiteRenderer.templatePagePath
    }

    var previewTagPath: String {
        previewTagSlug.isEmpty ? TagSettings.path : TagSettings.path(previewTagSlug)
    }

    var selectedPage: ContentItem? {
        guard let selectedPageID else { return nil }
        return site?.items.first { $0.id == selectedPageID }
    }
    /// Watches the site folder so the Files page follows changes made in Finder.
    private var folderWatcher: FolderWatcher?
    /// The Help Center article shown in the right column.
    var helpArticleID: String?

    // GitHub
    /// Accounts signed in on this Mac, by login.
    private(set) var accounts: [GitHubAccount] = []
    /// Their tokens, loaded from the Keychain.
    private var tokens: [String: String] = [:]
    private static let defaultAccountKey = "defaultGitHubAccount"
    /// The account used for new links and Open from GitHub unless another is picked.
    var defaultAccountLogin: String? = UserDefaults.standard.string(forKey: defaultAccountKey) {
        didSet { UserDefaults.standard.set(defaultAccountLogin, forKey: Self.defaultAccountKey) }
    }
    private(set) var gitAvailable = true
    private(set) var isWorking = false
    private(set) var workMessage: String?
    private(set) var lastPublished: Date?
    /// How this Mac compares with GitHub, for linked sites.
    private(set) var syncStatus: SyncStatus?
    private(set) var isCheckingSync = false
    /// Whether public/ is current, for sites not linked to GitHub.
    private(set) var buildState: BuildState?

    /// Saved styles on this Mac, shared by all sites.
    private(set) var styles: [SavedStyle] = []
    /// This site's own look, kept while trying saved styles so the user can
    /// switch back to it. Held until the app quits or another site opens.
    private(set) var unsavedStyle: ThemeSettings?
    private let styleLibrary: StyleLibrary

    private var dirty: Set<URL> = []
    private var configDirty = false
    private var themeDirty = false
    /// False when the theme's stylesheet predates the Theming panel and
    /// ignores its font, corner and width settings.
    /// Theme files (relative paths) made before newer CardStock features,
    /// such as Theming settings or the editable Home page.
    private(set) var outdatedThemeFiles: [String] = [] { didSet { scheduleHealthCount() } }
    private var saveTask: Task<Void, Never>?

    private static let lastSiteKey = "lastSitePath"

    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    private static let lastPublishedKey = "lastPublished"

    init(styleLibrary: StyleLibrary = .standard) {
        self.styleLibrary = styleLibrary
        styles = styleLibrary.load()
        // When the app is only hosting unit tests, leave the Keychain and the
        // user's last site alone (and avoid a Keychain password prompt).
        guard !Self.isRunningTests else { return }
        loadAccounts()
        if let path = UserDefaults.standard.string(forKey: Self.lastSiteKey) {
            let url = URL(filePath: path, directoryHint: .isDirectory)
            if Site.isSite(url) { open(url) }
        }
        Task {
            gitAvailable = await Git.isAvailable()
            await migrateLegacyToken()
            await refreshAccounts()
        }
    }

    // MARK: - Opening

    func open(_ url: URL) {
        saveNow()
        do {
            // Sites made before page types: everything moves into pages/.
            var migrated = SiteMigration.Result()
            var movedAddresses = 0
            if Site.isSite(url) {
                do {
                    migrated = try SiteMigration.run(in: url)
                } catch {
                    errorMessage = "Couldn't move posts and projects into pages/: \(error.localizedDescription)"
                }
            }
            // Sites made before the editable Home page get one.
            if Site.isSite(url), let config = try? Site.load(from: url).config {
                try? Site.ensureHomePage(in: url, description: config.description)
                try? Site.ensureTemplatePage(in: url)
                try? Site.ensureSearchPage(in: url)
                try? PageLayout.ensureLayouts(in: url)
                // Sites from before 0.6: pages move to /pages/ and /<collection>/pages/.
                do {
                    movedAddresses = try SiteMigration.moveAddresses(in: url)
                } catch {
                    errorMessage = "Couldn't move pages to their new addresses: \(error.localizedDescription)"
                }
            }
            site = try Site.load(from: url)
            // Older sites get a project file so they can be opened by double-clicking.
            try? ProjectSettings.ensureProjectFile(in: url)
            project = ProjectSettings.load(from: url)
            LocalData.prepare(in: url)
            chosenAccount = LocalData.gitHubAccount(in: url)
            selectedFileIDs = []
            selectedPageID = nil
            imageUndo = [:]
            storage = nil
            githubRepoBytes = nil
            refreshFiles()
            folderWatcher = FolderWatcher(url: url, latency: 1) { [weak self] in self?.refreshFiles() }
            scheduledPublish = ScheduledPublish.load(from: url)
            armSchedule()
            // Start on the launcher.
            selection = .start
            if !Self.isRunningTests {
                UserDefaults.standard.set(url.path, forKey: Self.lastSiteKey)
            }
            lastPublished = Self.lastPublishedDates()[url.path]
            checkStylesheet()
            moveWebFontsOutOfTheme()
            unsavedStyle = nil
            styleChoice = nil
            syncStatus = nil
            refreshStatus(fetch: true)
            startSyncPolling()
            statusMessage = nil
            revision += 1
            if !migrated.isEmpty {
                var parts: [String] = []
                if migrated.posts > 0 { parts.append("\(migrated.posts) \(migrated.posts == 1 ? "post" : "posts")") }
                if migrated.projects > 0 { parts.append("\(migrated.projects) \(migrated.projects == 1 ? "project" : "projects")") }
                statusMessage = "Moved \(ListFormatter.localizedString(byJoining: parts)) into pages/. Projects are now static pages."
            }
            if movedAddresses > 0 {
                statusMessage = "Pages have new addresses: /pages/name/, and /blog/pages/name/ (and so on) for pages in a collection. Links in your pages, top bar and footer were updated, and the old addresses redirect to the new ones."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Handles files opened from Finder: a site's .cardstock project file,
    /// a site folder, or style files to import.
    func handleOpen(_ urls: [URL]) {
        let styleExtensions = [StyleLibrary.fileExtension, "cardstocktheme"]
        let styleFiles = urls.filter { styleExtensions.contains($0.pathExtension.lowercased()) }
        if !styleFiles.isEmpty {
            let imported = importStyles(from: styleFiles)
            if !imported.isEmpty && site != nil { showConfiguration(.templates) }
        }
        for url in urls where !styleFiles.contains(url) {
            if url.pathExtension.lowercased() == ProjectSettings.fileExtension {
                open(url.deletingLastPathComponent())
            } else if Site.isSite(url) {
                open(url)
            } else {
                errorMessage = "“\(url.lastPathComponent)” isn't a CardStock site."
            }
        }
    }

    func createSite(at url: URL) {
        do {
            try StarterSite.create(at: url, title: url.lastPathComponent)
            open(url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Shows the Open from GitHub sheet.
    var isShowingOpenFromGitHub = false

    /// Downloads a site from GitHub into `parent` and opens it. A site
    /// already downloaded there is just opened. Returns true when it opened.
    @discardableResult
    func downloadSite(_ repo: GitHubClient.Repo, into parent: URL, account login: String) async -> Bool {
        guard let token = tokens[login] else { return false }
        let folder = parent.appending(path: SiteDownloader.folderName(for: repo.fullName), directoryHint: .isDirectory)
        if Site.isSite(folder), ProjectSettings.load(from: folder).github?.repo == repo.fullName {
            if LocalData.gitHubAccount(in: folder) == nil { LocalData.setGitHubAccount(login, in: folder) }
            open(folder)
            return site?.root == folder
        }
        let link = ProjectSettings.GitHubLink(repo: repo.fullName, branch: repo.defaultBranch ?? "main")
        return await perform("Downloading \(repo.fullName)…") {
            let user = try await self.user(for: login)
            try await SiteDownloader.download(link, to: folder, token: token, user: user)
            self.open(folder)
            self.showToast("Downloaded \(repo.fullName).")
        }
    }

    func close() {
        saveNow()
        site = nil
        selection = nil
        files = []
        folderWatcher = nil
        storage = nil
        githubRepoBytes = nil
        scheduledPublish = nil
        armSchedule()
        syncPoller?.cancel()
        syncPoller = nil
        project = ProjectSettings()
        if !Self.isRunningTests {
            UserDefaults.standard.removeObject(forKey: Self.lastSiteKey)
        }
    }

    /// Reloads everything from disk, keeping the selection when possible.
    func reload() {
        guard let root = site?.root else { return }
        saveNow()
        let selected = selection
        open(root)
        switch selected {
        case .item(let id) where site?.items.contains(where: { $0.id == id }) == true:
            selection = selected
        case .start, .status, .configuration, .publish, .pages, .files, .help:
            selection = selected
        default:
            break
        }
    }

    // MARK: - Items

    var selectedItem: ContentItem? {
        guard case .item(let id) = selection else { return nil }
        return site?.items.first { $0.id == id }
    }

    func update(_ item: ContentItem) {
        guard let i = site?.items.firstIndex(where: { $0.id == item.id }), site?.items[i] != item else { return }
        site?.items[i] = item
        dirty.insert(item.id)
        revision += 1
        scheduleSave()
    }

    func updateConfig(_ config: SiteConfig) {
        guard site != nil, site?.config != config else { return }
        site?.config = config
        configDirty = true
        revision += 1
        scheduleSave()
    }

    func updateTheme(_ theme: ThemeSettings) {
        guard site != nil, site?.theme != theme else { return }
        site?.theme = theme
        themeDirty = true
        revision += 1
        scheduleSave()
    }

    // MARK: - Styles

    /// A row in the Styles list.
    enum StyleChoice: Hashable {
        case unsaved
        case saved(UUID)
        case builtInDefault
    }

    /// The style the user last clicked. Remembered so that styles with
    /// identical settings can still be told apart.
    private var styleChoice: StyleChoice?

    /// The site's current theming (defaults when it has no theme.json).
    var currentTheme: ThemeSettings { site?.theme ?? ThemeSettings() }

    /// Which style row is selected: the one the user picked, as long as the
    /// site still has exactly its settings; otherwise the first match.
    var currentStyleChoice: StyleChoice {
        let look = currentTheme.look
        if let styleChoice, settings(for: styleChoice)?.look == look { return styleChoice }
        if look == ThemeSettings() { return .builtInDefault }
        if let match = styles.first(where: { $0.theme.look == look }) { return .saved(match.id) }
        return .unsaved
    }

    private func settings(for choice: StyleChoice) -> ThemeSettings? {
        switch choice {
        case .unsaved: unsavedStyle
        case .saved(let id): styles.first { $0.id == id }?.theme
        case .builtInDefault: ThemeSettings()
        }
    }

    /// The selected saved style, if a saved style is selected.
    var activeStyle: SavedStyle? {
        guard case .saved(let id) = currentStyleChoice else { return nil }
        return styles.first { $0.id == id }
    }

    func applyDefaultStyle() {
        keepUnsavedLook()
        styleChoice = .builtInDefault
        updateTheme(ThemeSettings())
        statusMessage = "Using CardStock's default template."
    }

    private func keepUnsavedLook() {
        if currentStyleChoice == .unsaved {
            unsavedStyle = currentTheme
        }
    }

    /// Switches back to the unsaved look.
    func applyUnsavedStyle() {
        guard let unsavedStyle else { return }
        styleChoice = .unsaved
        updateTheme(unsavedStyle)
        statusMessage = "Using this site's unsaved template."
    }

    func saveCurrentStyle(as name: String) {
        let set = SavedStyle(name: StyleLibrary.uniqueName(name, existing: styles), theme: portableTheme(currentTheme))
        storeStyle(set)
        styleChoice = .saved(set.id)
        if unsavedStyle == set.theme { unsavedStyle = nil }
    }

    /// Saves the unsaved look as a new style without switching to it.
    func saveUnsavedStyle(as name: String) {
        guard let theme = unsavedStyleTheme else { return }
        storeStyle(SavedStyle(name: StyleLibrary.uniqueName(name, existing: styles), theme: portableTheme(theme)))
        if unsavedStyle == theme { unsavedStyle = nil }
    }

    /// The look shown as "Unsaved Style": the current theming when it matches
    /// no saved style, otherwise the one kept from before switching.
    var unsavedStyleTheme: ThemeSettings? {
        currentStyleChoice == .unsaved ? currentTheme : unsavedStyle
    }

    /// True when the CardStock Default row is selected.
    var isUsingDefaultStyle: Bool {
        currentStyleChoice == .builtInDefault
    }

    /// Copies a style's settings into this site. An unsaved look is kept so
    /// the user can switch back to it.
    func applyStyle(_ set: SavedStyle) {
        keepUnsavedLook()
        styleChoice = .saved(set.id)
        addWebFontsToSite(set.theme.customFonts)
        updateTheme(set.theme.look)
        statusMessage = "Using the “\(set.name)” template."
    }

    /// Overwrites a set with this site's current theming.
    func updateStyle(_ set: SavedStyle) {
        var updated = set
        updated.theme = portableTheme(currentTheme)
        updated.savedAt = .now
        storeStyle(updated)
    }

    func renameStyle(_ set: SavedStyle, to name: String) {
        let others = styles.filter { $0.id != set.id }
        var updated = set
        updated.name = StyleLibrary.uniqueName(name, existing: others)
        storeStyle(updated)
    }

    func deleteStyle(_ set: SavedStyle) {
        do {
            try styleLibrary.delete(set.id)
            styles = styleLibrary.load()
        } catch {
            errorMessage = "Couldn't delete the template: \(error.localizedDescription)"
        }
    }

    func exportStyle(_ set: SavedStyle, to url: URL) {
        do {
            try StyleLibrary.exportData(set).write(to: url, options: .atomic)
            statusMessage = "Exported “\(set.name)”."
        } catch {
            errorMessage = "Couldn't export the template: \(error.localizedDescription)"
        }
    }

    /// Adds sets from exported files. Returns the imported sets.
    @discardableResult
    func importStyles(from urls: [URL]) -> [SavedStyle] {
        var imported: [SavedStyle] = []
        var problems: [String] = []
        for url in urls {
            do {
                var set = try StyleLibrary.importSet(from: url)
                set.name = StyleLibrary.uniqueName(set.name, existing: styles + imported)
                try styleLibrary.save(set)
                imported.append(set)
            } catch {
                problems.append(error.localizedDescription)
            }
        }
        styles = styleLibrary.load()
        if !problems.isEmpty { errorMessage = problems.joined(separator: "\n") }
        if !imported.isEmpty {
            statusMessage = imported.count == 1
                ? "Imported “\(imported[0].name)”."
                : "Imported \(imported.count) templates."
        }
        return imported
    }

    /// A copy of the look that carries the web fonts it uses, so the style
    /// works when shared or used on another site.
    private func portableTheme(_ theme: ThemeSettings) -> ThemeSettings {
        var copy = theme.look
        copy.customFonts = theme.usedFonts(from: site?.webFonts ?? [])
        return copy
    }

    // MARK: - Web fonts

    /// Web fonts in this site's font menus (saved in theme/fonts.json).
    var webFonts: [ThemeSettings.CustomFont] { site?.webFonts ?? [] }

    /// Looks up a pasted link and adds its fonts to this site. Returns the
    /// fonts that were added; throws if the link has no fonts.
    @discardableResult
    func addWebFont(link: String) async throws -> [ThemeSettings.CustomFont] {
        let found = try await WebFontLookup.lookUp(link)
        let added = found.filter { font in !webFonts.contains { $0.id == font.id } }
        guard !added.isEmpty else {
            let names = found.map(\.family).joined(separator: ", ")
            throw SiteError("\(names) \(found.count == 1 ? "is" : "are") already in the font menus.")
        }
        addWebFontsToSite(added)
        return added
    }

    func removeWebFont(_ font: ThemeSettings.CustomFont) {
        guard site != nil else { return }
        site?.webFonts.removeAll { $0.id == font.id }
        saveWebFonts()
        // Anything using it goes back to the default font.
        var theme = currentTheme
        theme.customFonts.removeAll { $0.id == font.id }
        let defaults = ThemeSettings()
        if theme.bodyFont == font.id { theme.bodyFont = defaults.bodyFont }
        if theme.headingFont == font.id { theme.headingFont = defaults.headingFont }
        if theme.navFont == font.id { theme.navFont = "" }
        if site?.theme != nil || theme != ThemeSettings() { updateTheme(theme) }
        revision += 1
    }

    func setWebFontStyle(_ font: ThemeSettings.CustomFont, _ style: ThemeSettings.CustomFont.Style) {
        guard let i = site?.webFonts.firstIndex(where: { $0.id == font.id }) else { return }
        site?.webFonts[i].style = style
        saveWebFonts()
        revision += 1
    }

    private func addWebFontsToSite(_ fonts: [ThemeSettings.CustomFont]) {
        let new = fonts.filter { font in !webFonts.contains { $0.id == font.id } }
        guard !new.isEmpty else { return }
        site?.webFonts += new
        saveWebFonts()
        revision += 1
    }

    private func saveWebFonts() {
        do {
            try site?.saveWebFonts()
        } catch {
            errorMessage = "Couldn't save theme/fonts.json: \(error.localizedDescription)"
        }
    }

    /// Sites made before fonts.json kept web fonts inside theme.json. Move
    /// them into fonts.json so switching styles never drops them.
    private func moveWebFontsOutOfTheme() {
        guard let theme = site?.theme, !theme.customFonts.isEmpty else { return }
        addWebFontsToSite(theme.customFonts)
        updateTheme(theme.look)
        saveNow()
    }

    // MARK: - Toasts

    /// A short message shown at the bottom of the window.
    private(set) var toast: String?
    private var toastTask: Task<Void, Never>?

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    private func storeStyle(_ set: SavedStyle) {
        do {
            try styleLibrary.save(set)
            styles = styleLibrary.load()
        } catch {
            errorMessage = "Couldn't save the template: \(error.localizedDescription)"
        }
    }

    /// Replaces outdated theme files with the current starter versions.
    /// The old files go to the Trash.
    func updateThemeFiles() {
        guard let root = site?.root,
              let starter = Bundle.main.url(forResource: "StarterSite", withExtension: nil)
        else { return }
        do {
            for file in outdatedThemeFiles {
                let target = root.appending(path: file)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.trashItem(at: target, resultingItemURL: nil)
                }
                try FileManager.default.copyItem(at: starter.appending(path: file), to: target)
            }
            checkStylesheet()
            revision += 1
            showToast("Theme files updated.")
        } catch {
            errorMessage = "Couldn't update the theme files: \(error.localizedDescription)"
        }
    }

    private func checkStylesheet() {
        guard let root = site?.root else { return }
        func read(_ path: String) -> String {
            (try? String(contentsOf: root.appending(path: path), encoding: .utf8)) ?? ""
        }
        var outdated: [String] = []
        let css = read("theme/assets/style.css")
        if !(css.contains("var(--font-body)") && css.contains("var(--h1-size)") && css.contains(".content small") && css.contains(".site-footer .rss") && css.contains(".footer-logo-row") && css.contains(".footer-menu") && css.contains(".button.buy") && css.contains(".footer-row") && css.contains("--dot-size") && css.contains(".site-bar") && css.contains(".bar-slot") && css.contains("var(--button-radius)") && css.contains("var(--nav-size)") && css.contains("var(--nav-pressed)") && css.contains("a.nav-button") && css.contains("var(--navbtn-icon)") && css.contains(".nav-overlay") && css.contains("var(--gutter)")) {
            outdated.append("theme/assets/style.css")
        }
        if !read("theme/home.html").contains("page.content") {
            outdated.append("theme/home.html")
        }
        let base = read("theme/base.html")
        if !(base.contains("footer.enabled") && base.contains(#"class="rss""#) && base.contains("footer.logo") && base.contains("footer.menus") && base.contains("footer-row") && base.contains("footer.attribution") && base.contains("site-bar") && base.contains("bar-slot") && base.contains("nav-button") && base.contains("nav-overlay")) {
            outdated.append("theme/base.html")
        }
        // Older themes' post template (sites made since 0.5 use item.html).
        let post = read("theme/post.html")
        if !post.isEmpty && !post.contains("categoryLinks") {
            outdated.append("theme/post.html")
        }
        // The Template page (preview only) gained images and a drop-down menu.
        let template = read("theme/template.html")
        if !template.isEmpty && !template.contains("theme-images") {
            outdated.append("theme/template.html")
        }
        // Templates for page types; until they're added the built-in ones are used.
        for name in SiteRenderer.newerTemplateNames where read("theme/\(name).html").isEmpty {
            outdated.append("theme/\(name).html")
        }
        outdatedThemeFiles = outdated
    }

    /// Makes a new page and (unless `open` is false) opens it. Returns its
    /// address. Items of dated collections get today's date and start as
    /// drafts; items start in their collection's item layout.
    @discardableResult
    func newItem(_ kind: ContentKind, title: String, open: Bool = true) -> String? {
        guard let site else { return nil }
        let folder = site.root.appending(path: ContentKind.folder)
        let base = Site.slugify(title)
        let unavailable = site.unavailableSlugs
        var slug = base
        var n = 2
        while FileManager.default.fileExists(atPath: folder.appending(path: "\(slug).md").path)
                || unavailable.contains(slug) {
            slug = "\(base)-\(n)"
            n += 1
        }

        var fm = FrontMatter()
        fm["title"] = .string(title)
        if kind != .page { fm["type"] = .string(kind.rawValue) }
        if kind.isItem, let collection = site.collection(for: kind) {
            if collection.dated {
                fm["date"] = .string(Self.today())
                fm["draft"] = .bool(true)
            }
            if !collection.itemLayout.isEmpty { fm["layout"] = .string(collection.itemLayout) }
        }
        let linkMenu = kind == .links
        return write(fm, body: linkMenu ? LinkMenu.starterBody + "\n" : "", to: folder.appending(path: "\(slug).md"),
                     open: open) ? kind.path(for: slug) : nil
    }

    /// Writes a new page file, adds it to the site and (optionally) opens it.
    /// Never replaces a file that's already there.
    private func write(_ fm: FrontMatter, body: String, to url: URL, open: Bool) -> Bool {
        if let existing = site?.items.first(where: { $0.fileURL.standardizedFileURL == url.standardizedFileURL })
            ?? (FileManager.default.fileExists(atPath: url.path) ? ContentItem(fileURL: url, text: "") : nil) {
            errorMessage = "There's already a page in pages/\(url.lastPathComponent) (“\(existing.title)”), so CardStock didn't replace it."
            return false
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FrontMatter.serialize(fm, body: body).write(to: url, atomically: true, encoding: .utf8)
            let text = try String(contentsOf: url, encoding: .utf8)
            // Build the new list first: reading and writing `site` in one
            // statement is an exclusive-access violation.
            let items = Site.sorted((site?.items ?? []).filter { $0.id != url } + [ContentItem(fileURL: url, text: text)])
            site?.items = items
            if open { selection = .item(url) }
            revision += 1
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Collections

    /// Adds a collection and its main page (pages/<id>.md), and lets search
    /// find its pages.
    func addCollection(_ collection: ContentCollection) {
        guard var config = site?.config, let root = site?.root else { return }
        config.collections.append(collection)
        if !config.search.kinds.contains(collection.itemType) { config.search.kinds.append(collection.itemType) }
        updateConfig(config)
        saveNow()
        let url = root.appending(path: "\(ContentKind.folder)/\(collection.id).md")
        if !FileManager.default.fileExists(atPath: url.path) {
            var fm = FrontMatter()
            fm["type"] = .string(ContentKind.mainType)
            fm["title"] = .string(collection.name)
            _ = write(fm, body: "", to: url, open: false)
        }
        configCollectionID = collection.id
    }

    /// Ensures a collection's main page has a file, then opens it to edit
    /// its title and text.
    func openMainPage(of collection: ContentCollection) {
        guard let site else { return }
        if let page = site.mainPage(of: collection) {
            selection = .item(page.id)
            return
        }
        // Another page already has the main page's file name.
        if let other = site.items.first(where: { $0.slug == collection.id }) {
            errorMessage = "The \(collection.name) main page would be pages/\(collection.id).md, but that file is already the page “\(other.title)”. Rename or remove that file in Finder, then try again. Until then, \(collection.mainPath) lists the \(collection.itemsName.lowercased()) under the title “\(collection.name)”."
            return
        }
        var fm = FrontMatter()
        fm["type"] = .string(ContentKind.mainType)
        fm["title"] = .string(collection.name)
        _ = write(fm, body: "", to: site.root.appending(path: "\(ContentKind.folder)/\(collection.id).md"), open: true)
    }

    /// Removes a collection. Its pages stay, as static pages (the main page
    /// keeps its address; items and categories move to /<name>/).
    func removeCollection(_ id: String) {
        guard var config = site?.config, let items = site?.items else { return }
        for var item in items where item.kind.collectionID == id {
            item.kind = .page
            item.categories = []
            update(item)
        }
        config.collections.removeAll { $0.id == id }
        config.search.kinds.removeAll { $0 == ContentCollection.itemType(id) || $0 == ContentCollection.categoryType(id) }
        updateConfig(config)
        if configCollectionID == id { configCollectionID = config.collections.first?.id ?? "" }
    }

    // MARK: - Tags

    /// Renames a tag on every page and in site.json. Renaming to a tag that
    /// exists merges the two.
    func renameTag(_ slug: String, to newName: String) {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, var config = site?.config, let items = site?.items else { return }
        for var item in items where item.hasTag(slug) {
            item.tags = item.tags(renaming: slug, to: name)
            update(item)
        }
        config.tags.rename(slug, to: name)
        updateConfig(config)
        updateFileTags { $0.rename(slug, to: name) }
        if previewTagSlug == slug { previewTagSlug = TagSettings.slug(name) }
    }

    /// Takes a tag off every page and out of site.json.
    func deleteTag(_ slug: String) {
        guard var config = site?.config, let items = site?.items else { return }
        for var item in items where item.hasTag(slug) {
            item.tags = item.tags.filter { TagSettings.slug($0) != slug }
            update(item)
        }
        config.tags.list.removeAll { $0.slug == slug }
        updateConfig(config)
        updateFileTags { $0.remove(slug) }
        if previewTagSlug == slug { previewTagSlug = "" }
    }

    /// Changes the tags on files in media/ and saves media.json right away.
    func updateFileTags(_ change: (inout MediaTags) -> Void) {
        guard var tags = site?.mediaTags, let root = site?.root else { return }
        let before = tags
        change(&tags)
        guard tags != before else { return }
        site?.mediaTags = tags
        do {
            try tags.save(to: root)
        } catch {
            errorMessage = "Couldn't save the file tags (media.json): \(error.localizedDescription)"
        }
        refreshFiles()
        revision += 1
        refreshStatus(fetch: false)
    }

    /// Adds and removes tags on files.
    func changeTags(of files: [MediaFile], adding: [String], removing: [String]) {
        updateFileTags { tags in
            for file in files {
                tags[file.path] = TagSettings.changing(tags[file.path], adding: adding, removing: removing)
            }
        }
    }

    /// Sets a tag's description (kept in site.json).
    func setTagDescription(_ slug: String, name: String, description: String) {
        guard var config = site?.config else { return }
        if let i = config.tags.list.firstIndex(where: { $0.slug == slug }) {
            config.tags.list[i].description = description
        } else {
            config.tags.list.append(.init(name: name, description: description))
        }
        updateConfig(config)
    }

    /// Moves an item's file to the Trash.
    func delete(_ id: URL) {
        // Home and the 404 page are needed by every site.
        if let item = site?.items.first(where: { $0.id == id }), !item.canBeDeleted { return }
        do {
            try FileManager.default.trashItem(at: id, resultingItemURL: nil)
            dirty.remove(id)
            site?.items.removeAll { $0.id == id }
            if selection == .item(id) { selection = nil }
            if selectedPageID == id { selectedPageID = site?.home?.id }
            revision += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Saving

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        guard let site else { return }
        let wroteSomething = !dirty.isEmpty || themeDirty || configDirty
        defer { if wroteSomething { refreshStatus(fetch: false) } }
        for id in dirty {
            guard let item = site.items.first(where: { $0.id == id }) else { continue }
            do {
                try item.fileText.write(to: item.fileURL, atomically: true, encoding: .utf8)
            } catch {
                errorMessage = "Couldn't save \(item.fileURL.lastPathComponent): \(error.localizedDescription)"
                return
            }
        }
        dirty.removeAll()
        if themeDirty, let theme = site.theme {
            do {
                try theme.save(to: site.root)
                themeDirty = false
            } catch {
                errorMessage = "Couldn't save theme.json: \(error.localizedDescription)"
            }
        }
        if configDirty {
            do {
                try site.saveConfig()
                configDirty = false
            } catch {
                errorMessage = "Couldn't save site.json: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Files

    /// Re-reads the media folder (and where each file is used).
    func refreshFiles() {
        guard var site else { files = []; return }
        // media.json may have changed outside CardStock (Finder, another Mac).
        let tags = MediaTags.load(from: site.root)
        if tags != site.mediaTags {
            self.site?.mediaTags = tags
            site.mediaTags = tags
        }
        let scanned = MediaLibrary.scan(site)
        if scanned != files { files = scanned }
    }

    /// Copies Markdown that shows the files (one paragraph each), ready to
    /// paste into a page.
    func copyMarkdown(for files: [MediaFile]) {
        guard !files.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(files.map(MediaLibrary.markdown(for:)).joined(separator: "\n\n"), forType: .string)
        showToast(files.count == 1 ? "Copied. Paste it into a page or post." : "Copied \(files.count) files. Paste them into a page or post.")
    }

    /// Copies files into the site's media/files folder.
    /// Copies files into media/files. Returns the files as added.
    @discardableResult
    func addFiles(_ urls: [URL]) -> [MediaFile] {
        guard let root = site?.root, !urls.isEmpty else { return [] }
        do {
            let added = try MediaLibrary.addFiles(urls, to: root)
            refreshFiles()
            showToast(added.count == 1 ? "Added \((added[0] as NSString).lastPathComponent)." : "Added \(added.count) files.")
            return added.compactMap { path in files.first { $0.path == path } }
        } catch {
            errorMessage = "Couldn't add the files: \(error.localizedDescription)"
            return []
        }
    }

    // MARK: - Image editing

    /// Bumped after an image changes on disk, so previews reload it.
    private(set) var mediaRevision = 0
    private(set) var isEditingImage = false
    /// Copies of images from before each edit, newest last, for Undo.
    private var imageUndo: [String: [URL]] = [:]

    func canUndoImageEdit(_ file: MediaFile) -> Bool { !(imageUndo[file.path] ?? []).isEmpty }

    /// Applies a Core Image edit to the file (and rebuilds its inline version).
    func editImage(_ file: MediaFile, _ edit: ImageEditor.Edit) {
        guard let root = site?.root, !isEditingImage else { return }
        let large = root.appending(path: file.path)
        let small = file.smallPath.map { root.appending(path: $0) }
        isEditingImage = true
        Task {
            do {
                let backup = try backUp(file, root: root)
                try await Task.detached(priority: .userInitiated) {
                    try ImageEditor.apply(edit, to: large, small: small)
                }.value
                imageUndo[file.path, default: []].append(backup)
                finishImageEdit()
            } catch {
                isEditingImage = false
                errorMessage = "Couldn't edit \(file.name): \(error.localizedDescription)"
            }
        }
    }

    /// Saves the photo's subject on a transparent background as a new PNG
    /// and selects it.
    func removeBackground(_ file: MediaFile) {
        guard let root = site?.root, !isEditingImage else { return }
        let url = root.appending(path: file.path)
        isEditingImage = true
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try ImageEditor.removeBackground(from: url)
                }.value
                let path = String(result.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
                finishImageEdit()
                selectedFileIDs = [path]
                showToast("Saved the cut-out as \(result.lastPathComponent).")
            } catch {
                isEditingImage = false
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Puts the image back as it was before the last edit.
    func undoImageEdit(_ file: MediaFile) {
        guard let root = site?.root, let backup = imageUndo[file.path]?.popLast() else { return }
        let fm = FileManager.default
        for path in file.allPaths {
            let saved = backup.appending(path: (path as NSString).lastPathComponent)
            let target = root.appending(path: path)
            guard fm.fileExists(atPath: saved.path) else { continue }
            try? fm.removeItem(at: target)
            try? fm.copyItem(at: saved, to: target)
        }
        try? fm.removeItem(at: backup)
        finishImageEdit()
    }

    private func backUp(_ file: MediaFile, root: URL) throws -> URL {
        let backup = FileManager.default.temporaryDirectory.appending(path: "CardStock-Undo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        for path in file.allPaths {
            try FileManager.default.copyItem(at: root.appending(path: path),
                                             to: backup.appending(path: (path as NSString).lastPathComponent))
        }
        return backup
    }

    private func finishImageEdit() {
        isEditingImage = false
        mediaRevision += 1
        refreshFiles()
        revision += 1
    }

    /// Copies a file (both sizes, for optimized images) and selects the copy.
    func duplicateFile(_ file: MediaFile) {
        guard let root = site?.root else { return }
        do {
            let path = try MediaLibrary.duplicate(file, root: root)
            refreshFiles()
            selectedFileIDs = [path]
            showToast("Made a copy: \((path as NSString).lastPathComponent).")
        } catch {
            errorMessage = "Couldn't duplicate \(file.name): \(error.localizedDescription)"
        }
    }

    /// Moves a file to the Mac's Trash. The next publish removes it from GitHub.
    func deleteFile(_ file: MediaFile) {
        guard let root = site?.root else { return }
        do {
            try MediaLibrary.moveToTrash(file, root: root)
            if !file.tags.isEmpty { updateFileTags { $0[file.path] = [] } }
            showToast("Moved \(file.name) to the Trash.")
        } catch {
            errorMessage = "Couldn't move \(file.name) to the Trash: \(error.localizedDescription)"
        }
        refreshFiles()
        revision += 1
        refreshStatus(fetch: false)
    }

    // MARK: - Storage

    /// How much space the site takes on this Mac.
    private(set) var storage: SiteStorage?
    /// The size GitHub reports for the linked repository, in bytes.
    private(set) var githubRepoBytes: Int64?
    private(set) var isMeasuringStorage = false

    /// Measures the site folder and asks GitHub for the repository's size.
    func refreshStorage() {
        guard let root = site?.root, !isMeasuringStorage else { return }
        isMeasuringStorage = true
        let token = token
        let repo = project.github?.repo
        Task {
            let measured = await Task.detached(priority: .utility) { SiteStorage.measure(root: root) }.value
            var remote: Int64?
            if let token, let repo, let kb = try? await GitHubClient(token: token).repo(repo).size {
                remote = Int64(kb) * 1024
            }
            isMeasuringStorage = false
            guard site?.root == root else { return }
            storage = measured
            githubRepoBytes = remote
        }
    }

    // MARK: - Dashboard

    /// When the site was published (from git history), or, for sites not on
    /// GitHub, the dates of published posts. For the activity calendar.
    private(set) var activityDates: [Date] = []
    /// True when `activityDates` comes from publishes rather than post dates.
    private(set) var activityIsPublishes = false

    func refreshActivity() {
        guard let site else { return }
        let root = site.root
        let postDates = SiteInsights.postDates(site)
        Task {
            let git = Git(root: root)
            var dates: [Date] = []
            if git.isRepository, let log = try? await git.run("log", "--format=%cI") {
                let parser = ISO8601DateFormatter()
                dates = log.split(separator: "\n").compactMap { parser.date(from: String($0)) }
            }
            guard self.site?.root == root else { return }
            activityIsPublishes = !dates.isEmpty
            activityDates = dates.isEmpty ? postDates : dates
        }
    }

    // MARK: - Help

    /// Shows a page of Configuration.
    func showConfiguration(_ page: ConfigPage) {
        configPage = page
        selection = .configuration
    }

    /// Shows the Help Center, optionally at a given article.
    func showHelp(_ articleID: String? = nil) {
        if let articleID { helpArticleID = articleID }
        selection = .help
    }

    /// Recounts Site Health's problems once changes settle.
    private func scheduleHealthCount() {
        healthTask?.cancel()
        healthTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.countHealthProblems()
        }
    }

    private func countHealthProblems() {
        let count = site.map { site in
            SiteInsights.healthChecks(site, files: files, outdatedThemeFiles: outdatedThemeFiles)
                .reduce(0) { $0 + ($1.passed ? 0 : $1.problems.count) }
        } ?? 0
        if count != healthProblemCount { healthProblemCount = count }
    }

    /// Follows a `cardstock:` link from a help article.
    func openAppLink(_ target: String) {
        switch target {
        case "configuration": selection = .configuration
        case "status": selection = .status
        case "theming": showConfiguration(.templates)
        case "layout": showConfiguration(.components)
        case _ where ConfigPage.allCases.contains { $0.linkName == target }:
            showConfiguration(ConfigPage.allCases.first { $0.linkName == target }!)
        case "publishing": selection = .publish
        case "files": selection = .files
        case "pages": selection = .pages
        case "home": if let home = site?.home { selection = .item(home.id) }
        default: break
        }
    }

    // MARK: - Website

    /// The Web Address from Site Details, with https:// added when missing.
    var websiteURL: URL? {
        guard let raw = site?.config.url.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let text = raw.contains("://") ? raw : "https://" + raw
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host() != nil else { return nil }
        return url
    }

    /// Opens the live site in the user's default browser. Without a web
    /// address, shows Site Details so one can be added.
    func openWebsite() {
        guard site != nil else { return }
        if let url = websiteURL {
            NSWorkspace.shared.open(url)
        } else {
            showConfiguration(.site)
            showToast("Add the site's web address to open it in your browser.")
        }
    }

    // MARK: - Building

    func build() {
        guard let site else { return }
        saveNow()
        do {
            let report = try SiteBuilder.build(site)
            var message = "Generated \(report.pageCount) pages of flat HTML in public/."
            if !report.warnings.isEmpty {
                message += " " + report.warnings.joined(separator: " ")
            }
            statusMessage = message
        } catch {
            errorMessage = "Generating flat HTML failed: \(error.localizedDescription)"
        }
        refreshStatus(fetch: false)
    }

    // MARK: - Status

    /// Updates the publish status: the build state for local sites, or the
    /// comparison with GitHub for linked ones.
    func refreshStatus(fetch: Bool) {
        guard let root = site?.root else { return }
        guard let link = project.github else {
            syncStatus = nil
            buildState = BuildState.check(root: root)
            return
        }
        buildState = nil
        let token = token
        let previous = syncStatus
        if fetch {
            isCheckingSync = true
            lastRemoteCheck = .now
        }
        Task {
            let status = await SyncStatus.check(root: root, token: token, branch: link.branch,
                                                fetch: fetch, previous: previous)
            if fetch { isCheckingSync = false }
            // Ignore results for a site that's no longer open.
            guard site?.root == root else { return }
            syncStatus = status
        }
    }

    // MARK: - Watching GitHub

    /// When GitHub was last asked for changes made on other Macs.
    private var lastRemoteCheck: Date?
    private var syncPoller: Task<Void, Never>?
    /// How often an open, linked site checks GitHub.
    static let syncInterval: Duration = .seconds(300)

    /// Asks GitHub for changes published from other Macs, unless it was
    /// asked within `minimumInterval` seconds. Skipped while publishing.
    func checkGitHubForUpdates(minimumInterval: TimeInterval = 60) {
        guard project.github != nil, isSignedIn, !isWorking, !isCheckingSync else { return }
        if let lastRemoteCheck, Date.now.timeIntervalSince(lastRemoteCheck) < minimumInterval { return }
        refreshStatus(fetch: true)
    }

    /// Undoes this Mac's edits to `paths` so updates from GitHub can come in
    /// cleanly. A copy of each edited file goes to the Mac's Trash first,
    /// named "… (edits from this Mac)", so nothing is lost.
    func useGitHubVersion(of paths: [String]) async {
        guard let root = site?.root else { return }
        saveNow()
        await perform("Keeping GitHub's version…") {
            let fm = FileManager.default
            let git = Git(root: root)
            let scratch = fm.temporaryDirectory.appending(path: "cardstock-edits-\(UUID().uuidString)")
            try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: scratch) }
            for path in paths {
                let file = root.appending(path: path)
                if fm.fileExists(atPath: file.path) {
                    let ext = file.pathExtension
                    let base = file.deletingPathExtension().lastPathComponent
                    let name = "\(base) (edits from this Mac)" + (ext.isEmpty ? "" : ".\(ext)")
                    let copy = scratch.appending(path: name)
                    try fm.copyItem(at: file, to: copy)
                    try fm.trashItem(at: copy, resultingItemURL: nil)
                }
                if (await git.attempt(["cat-file", "-e", "HEAD:\(path)"])).succeeded {
                    try await git.run("checkout", "HEAD", "--", path)
                } else {
                    // New on this Mac only: the copy in the Trash is the only one.
                    try? fm.removeItem(at: file)
                }
            }
            self.reload()
            self.showToast("Kept GitHub's version. Your edits are in the Trash.")
        }
        refreshStatus(fetch: false)
    }

    /// Checks GitHub every few minutes while a site is open.
    private func startSyncPolling() {
        syncPoller?.cancel()
        guard !Self.isRunningTests else { return }
        syncPoller = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.syncInterval)
                guard !Task.isCancelled else { return }
                self?.checkGitHubForUpdates()
            }
        }
    }

    // MARK: - GitHub accounts

    /// The account this site publishes with (see `GitHubAccounts.login`).
    /// For a site that isn't linked yet, the default account.
    var siteAccount: GitHubAccount? {
        let login = GitHubAccounts.login(for: project.github, chosen: chosenAccount, signedIn: accounts.map(\.login),
                                         defaultLogin: defaultAccountLogin)
        return accounts.first { $0.login == login }
    }

    /// The account chosen for the open site on this Mac (`.cardstock-local/`).
    private(set) var chosenAccount: String?

    /// The account chosen for the open site that isn't signed in any more.
    var missingSiteAccount: String? {
        guard project.github != nil, let chosenAccount, siteAccount == nil else { return nil }
        return chosenAccount
    }

    var defaultAccount: GitHubAccount? {
        accounts.first { $0.login.caseInsensitiveCompare(defaultAccountLogin ?? "") == .orderedSame } ?? accounts.first
    }

    /// The token for the open site's account.
    var token: String? { siteAccount.flatMap { tokens[$0.login] } }
    var githubUser: GitHubClient.User? { siteAccount?.user }
    var isSignedIn: Bool { token != nil }
    var hasAccounts: Bool { !accounts.isEmpty }

    func token(for login: String) -> String? { tokens[login] }

    private func loadAccounts() {
        let previous = Dictionary(uniqueKeysWithValues: accounts.map { ($0.login, $0.user) })
        var loaded: [GitHubAccount] = []
        var found: [String: String] = [:]
        for login in Keychain.savedLogins() {
            guard let token = Keychain.token(for: login) else { continue }
            found[login] = token
            loaded.append(GitHubAccount(login: login, user: previous[login] ?? nil))
        }
        tokens = found
        accounts = loaded
    }

    /// Fills in each account's name and ID from GitHub.
    func refreshAccounts() async {
        for (index, account) in accounts.enumerated() {
            guard let token = tokens[account.login],
                  let user = try? await GitHubClient(token: token).currentUser(),
                  index < accounts.count, accounts[index].login == account.login else { continue }
            accounts[index].user = user
        }
    }

    /// Before several accounts, the one token was saved without its login.
    /// Moves it under its account.
    private func migrateLegacyToken() async {
        guard let token = Keychain.token(for: Keychain.legacyAccount),
              let user = try? await GitHubClient(token: token).currentUser(),
              (try? Keychain.save(token, for: user.login)) != nil else { return }
        Keychain.delete(Keychain.legacyAccount)
        loadAccounts()
        if let index = accounts.firstIndex(where: { $0.login == user.login }) { accounts[index].user = user }
        if defaultAccountLogin == nil { defaultAccountLogin = user.login }
        refreshStatus(fetch: false)
    }

    /// The GitHub user for an account, asking GitHub when it isn't known yet.
    private func user(for login: String) async throws -> GitHubClient.User {
        if let user = accounts.first(where: { $0.login == login })?.user { return user }
        guard let token = tokens[login] else { throw SiteError("\(login) isn't signed in on this Mac.") }
        let user = try await GitHubClient(token: token).currentUser()
        if let index = accounts.firstIndex(where: { $0.login == login }) { accounts[index].user = user }
        return user
    }

    /// Checks the token with GitHub, then saves it in the Keychain under its
    /// account. Signing in again as the same account replaces its token.
    /// Returns the account's login.
    @discardableResult
    func signIn(token rawToken: String) async -> String? {
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }
        var login: String?
        await perform("Checking token…") {
            let user = try await GitHubClient(token: token).currentUser()
            try Keychain.save(token, for: user.login)
            self.loadAccounts()
            if let index = self.accounts.firstIndex(where: { $0.login == user.login }) {
                self.accounts[index].user = user
            }
            if self.defaultAccountLogin == nil || self.accounts.count == 1 {
                self.defaultAccountLogin = user.login
            }
            login = user.login
        }
        refreshStatus(fetch: true)
        return login
    }

    /// Removes an account's token from this Mac.
    func signOut(_ login: String) {
        Keychain.delete(login)
        loadAccounts()
        if defaultAccountLogin == login { defaultAccountLogin = accounts.first?.login }
        refreshStatus(fetch: false)
    }

    /// Chooses which account publishes the open site from this Mac.
    func setSiteAccount(_ login: String) {
        guard let root = site?.root, chosenAccount != login else { return }
        LocalData.setGitHubAccount(login, in: root)
        chosenAccount = login
        refreshStatus(fetch: true)
    }

    func recheckGit() async {
        gitAvailable = await Git.isAvailable()
    }

    // MARK: - Linking and publishing

    /// Creates a new repo on GitHub and links this site to it.
    func linkNewRepo(name: String, isPrivate: Bool, account login: String) async {
        guard let site, let token = tokens[login] else { return }
        await perform("Creating repository…") {
            let client = GitHubClient(token: token)
            let repo = try await client.createRepo(name: name, isPrivate: isPrivate, description: site.config.description)
            try await self.finishLink(repo: repo.fullName, account: login)
        }
    }

    /// Links this site to an existing, empty repo.
    func linkExistingRepo(_ fullName: String, account login: String) async {
        guard let token = tokens[login] else { return }
        var name = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://github.com/", with: "")
        if name.hasSuffix(".git") { name.removeLast(4) }
        if name.hasSuffix("/") { name.removeLast() }
        await perform("Checking repository…") {
            let client = GitHubClient(token: token)
            let repo = try await client.repo(name)
            guard try await client.isEmpty(repo.fullName) else {
                throw SiteError("\(repo.fullName) already has files in it. For now, CardStock can only link to an empty repository.")
            }
            try await self.finishLink(repo: repo.fullName, account: login)
        }
    }

    private func finishLink(repo: String, account login: String) async throws {
        guard let root = site?.root, let token = tokens[login] else { return }
        let user = try await user(for: login)
        saveNow()
        workMessage = "Uploading site to GitHub…"
        _ = try await Publisher(root: root, token: token).link(repo: repo, user: user)
        project = ProjectSettings.load(from: root)
        chosenAccount = LocalData.gitHubAccount(in: root)
        markPublished()
        refreshStatus(fetch: false)
        statusMessage = "Linked to \(repo) and published."
    }

    func unlink() async {
        guard let root = site?.root else { return }
        await perform("Unlinking…") {
            try await Publisher(root: root, token: self.token ?? "").unlink()
            self.project = ProjectSettings.load(from: root)
            self.statusMessage = "Unlinked from GitHub. The site still works locally."
            self.refreshStatus(fetch: false)
        }
    }

    @discardableResult
    func publish(message: String) async -> Bool {
        guard let root = site?.root, let token, let link = project.github, !isWorking else { return false }
        saveNow()
        setPublishIndicator(.publishing)
        let succeeded = await perform("Publishing…") {
            let user = try await self.user(for: self.siteAccount?.login ?? "")
            let outcome = try await Publisher(root: root, token: token).publish(link: link, user: user, message: message)
            if outcome.pulledChanges { self.reload() }
            self.markPublished()
            self.statusMessage = outcome.committed || outcome.pulledChanges
                ? "Published to \(link.repo)."
                : "Already up to date on GitHub."
            self.showToast(self.statusMessage ?? "Published.")
        }
        setPublishIndicator(succeeded ? .done : nil)
        // Also after a failed publish, so the page shows where things stand.
        refreshStatus(fetch: false)
        return succeeded
    }

    /// Shown next to Publishing in the sidebar: a spinner while publishing,
    /// then a green check that fades after a few seconds.
    enum PublishIndicator { case publishing, done, fading }
    private(set) var publishIndicator: PublishIndicator?
    private var publishIndicatorTask: Task<Void, Never>?

    private func setPublishIndicator(_ indicator: PublishIndicator?) {
        publishIndicatorTask?.cancel()
        publishIndicator = indicator
        guard indicator == .done else { return }
        publishIndicatorTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 1)) { self?.publishIndicator = .fading }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.publishIndicator = nil
        }
    }

    /// Runs `work`, showing `message` while it does. Returns false if it
    /// failed (the error is shown) or other work was already running.
    @discardableResult
    private func perform(_ message: String, _ work: () async throws -> Void) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        workMessage = message
        defer {
            isWorking = false
            workMessage = nil
        }
        do {
            try await work()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Scheduled publishing

    /// A publish set for later on this Mac, if any.
    private(set) var scheduledPublish: ScheduledPublish?
    private var scheduleTask: Task<Void, Never>?
    /// Keeps App Nap from delaying the scheduled publish.
    private var scheduleActivity: NSObjectProtocol?

    func schedulePublish(at date: Date, message: String) {
        setSchedule(ScheduledPublish(date: date, message: message))
        showToast("Publishing \(date.formatted(date: .abbreviated, time: .shortened)).")
    }

    func cancelScheduledPublish() {
        setSchedule(nil)
        showToast("Scheduled publish removed.")
    }

    /// After a failed attempt: try again now.
    func retryScheduledPublish() {
        guard var schedule = scheduledPublish else { return }
        schedule.failure = nil
        schedule.date = .now
        setSchedule(schedule)
    }

    private func setSchedule(_ schedule: ScheduledPublish?) {
        scheduledPublish = schedule
        if let root = site?.root {
            do {
                try ScheduledPublish.save(schedule, in: root)
            } catch {
                errorMessage = "Couldn't save the publish schedule: \(error.localizedDescription)"
            }
        }
        armSchedule()
    }

    /// Starts (or stops) waiting for the scheduled time. A time that passed
    /// while CardStock was closed or the Mac was asleep publishes right away.
    private func armSchedule() {
        scheduleTask?.cancel()
        scheduleTask = nil
        guard let schedule = scheduledPublish, schedule.failure == nil, !Self.isRunningTests else {
            if let scheduleActivity { ProcessInfo.processInfo.endActivity(scheduleActivity) }
            scheduleActivity = nil
            return
        }
        if scheduleActivity == nil {
            scheduleActivity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep, reason: "Scheduled publish")
        }
        let root = site?.root
        scheduleTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.site?.root == root else { return }
                let remaining = schedule.date.timeIntervalSinceNow
                // Wait while other work (a manual publish) is running.
                if remaining <= 0 && !self.isWorking {
                    await self.runScheduledPublish(schedule)
                    return
                }
                // Short naps so a wake from sleep is noticed quickly.
                try? await Task.sleep(for: .seconds(min(max(remaining, 1), 15)))
            }
        }
    }

    private func runScheduledPublish(_ schedule: ScheduledPublish) async {
        guard let root = site?.root else { return }
        // Clear it first: a publish that pulls changes reopens the site,
        // which would otherwise find the schedule and publish again.
        scheduledPublish = nil
        try? ScheduledPublish.save(nil, in: root)
        armSchedule()

        let failure: String?
        if project.github == nil {
            failure = "This site isn't linked to GitHub any more."
        } else if !isSignedIn {
            failure = "This Mac isn't signed in to GitHub."
        } else if await publish(message: schedule.message) {
            failure = nil
        } else {
            failure = errorMessage ?? "Publishing didn't finish."
        }

        guard site?.root == root else { return }
        if let failure {
            var failed = schedule
            failed.failure = failure
            setSchedule(failed)
        } else {
            showToast("Published automatically.")
        }
    }

    private func markPublished() {
        refreshActivity()
        guard let root = site?.root else { return }
        let now = Date.now
        lastPublished = now
        var dates = Self.lastPublishedDates()
        dates[root.path] = now
        UserDefaults.standard.set(dates, forKey: Self.lastPublishedKey)
    }

    private static func lastPublishedDates() -> [String: Date] {
        UserDefaults.standard.dictionary(forKey: lastPublishedKey) as? [String: Date] ?? [:]
    }

    static func today() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: .now)
    }
}
