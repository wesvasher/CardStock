import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Every file in the site's media folder: images added in the editor, files
/// added here, and anything copied into the folder in Finder. Copy a file's
/// Markdown to paste it into a page, or move it to the Trash.
struct FilesView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var filter = FileFilter.all
    /// Kept in the model so the preview column can show the selected file.
    private var selection: Set<MediaFile.ID> {
        get { model.selectedFileIDs }
        nonmutating set { model.selectedFileIDs = newValue }
    }
    @State private var sort = FileSort.newest
    @State private var pendingDelete: [MediaFile] = []
    @State private var isDropTargeted = false
    /// The folder being named: a new one (in `namingParent`) or a rename.
    @State private var naming: FolderNaming?
    @State private var folderName = ""
    @State private var pendingFolderDelete: String?

    private enum FolderNaming: Equatable {
        case new(parent: String)
        case rename(String)
    }

    /// The folder shown; `media` is the top.
    private var folder: String { model.filesFolder }

    /// Without a search or filter, the list shows one folder at a time.
    private var isBrowsing: Bool { query.isEmpty && filter == .all }

    /// The folders in the shown folder, by name (none while searching).
    private var subfolders: [String] {
        guard isBrowsing else { return [] }
        return model.mediaFolders.filter { MediaLibrary.parent(of: $0) == folder }
    }

    private var shown: [MediaFile] {
        let files = isBrowsing ? model.files.filter { $0.folder == folder } : model.files
        return FileFilter.apply(files, filter: filter, sort: sort, query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.files.isEmpty && model.mediaFolders.isEmpty {
                Divider()
                ContentUnavailableView {
                    Label("No Files Yet", systemImage: "folder")
                } description: {
                    Text("Images you add to pages appear here. You can also drag files here, or into the site's media folder in Finder.")
                } actions: {
                    Button("Add Files…", action: chooseFiles)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isBrowsing && shown.isEmpty && subfolders.isEmpty {
                Divider()
                ContentUnavailableView {
                    Label(folder == MediaLibrary.folderName ? "No Files Here" : "This Folder Is Empty", systemImage: "folder")
                } description: {
                    Text("Drag files here, add them, or move files into this folder with Move To in their menu.")
                } actions: {
                    Button("Add Files…", action: chooseFiles)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shown.isEmpty && subfolders.isEmpty {
                Divider()
                ContentUnavailableView {
                    Label("No Matching Files", systemImage: "magnifyingglass")
                } description: {
                    Text("No files match your search and filters.")
                } actions: {
                    Button(clearTitle) {
                        filter = .all
                        query = ""
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                table
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                    .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(Label("Add to Files", systemImage: "plus.circle.fill").font(.title3.bold()))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            model.addFiles(files, to: folder)
            return !files.isEmpty
        } isTargeted: { isDropTargeted = $0 }
        .onAppear {
            model.refreshFiles()
            // Start with a file selected so the preview isn't empty.
            let visible = Set(shown.map(\.id))
            if selection.intersection(visible).isEmpty, let first = shown.first {
                selection = [first.id]
            }
        }
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { !pendingDelete.isEmpty },
                                                              set: { if !$0 { pendingDelete = [] } })) {
            Button("Move to Trash", role: .destructive) {
                pendingDelete.forEach(model.deleteFile)
                selection.subtract(pendingDelete.map(\.id))
                pendingDelete = []
            }
        } message: {
            Text(deleteMessage)
        }
        .alert(isRenaming ? "Rename Folder" : "New Folder",
               isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Name", text: $folderName)
            Button("Cancel", role: .cancel) { naming = nil }
            Button(isRenaming ? "Rename" : "Create") { finishNaming() }
                .disabled(MediaLibrary.folderName(for: folderName) == nil)
        } message: {
            Text(namingMessage)
        }
        .confirmationDialog(folderDeleteTitle, isPresented: Binding(get: { pendingFolderDelete != nil },
                                                                    set: { if !$0 { pendingFolderDelete = nil } })) {
            Button("Move to Trash", role: .destructive) {
                if let path = pendingFolderDelete { model.trashFolder(path) }
                pendingFolderDelete = nil
            }
        } message: {
            Text(folderDeleteMessage)
        }
    }

    // MARK: - Folders

    private var isRenaming: Bool {
        if case .rename = naming { return true }
        return false
    }

    private func startNewFolder() {
        folderName = ""
        naming = .new(parent: folder)
    }

    private func startRename(_ path: String) {
        folderName = MediaLibrary.name(of: path)
        naming = .rename(path)
    }

    private var namingMessage: String {
        let address = MediaLibrary.folderName(for: folderName).map { "Its files' addresses will start with /\(namingParent)/\($0)/." }
            ?? "Folder names become part of your files' addresses, so they use lowercase letters, numbers and dashes."
        if case .rename = naming {
            return address + " Links to its files in your pages are updated."
        }
        return address
    }

    private var namingParent: String {
        switch naming {
        case .new(let parent): parent
        case .rename(let path): MediaLibrary.parent(of: path)
        case nil: folder
        }
    }

    private func finishNaming() {
        switch naming {
        case .new(let parent):
            if let path = model.newFolder(folderName, in: parent) { model.filesFolder = path }
        case .rename(let path):
            model.renameFolder(path, to: folderName)
        case nil:
            break
        }
        naming = nil
    }

    private var folderDeleteTitle: String {
        "Move “\(pendingFolderDelete.map(MediaLibrary.name(of:)) ?? "")” to the Trash?"
    }

    private var folderDeleteMessage: String {
        guard let path = pendingFolderDelete else { return "" }
        let inside = model.files.filter { MediaLibrary.isInside($0.path, path) }
        guard !inside.isEmpty else { return "It's empty. It goes to your Mac's Trash." }
        return "It and the \(inside.count) \(inside.count == 1 ? "file" : "files") in it go to your Mac's Trash. "
            + Self.deleteMessage(for: inside)
    }

    /// Files and folders being dragged, as one string (`cardstock-media:` and a path per line).
    private static let dragPrefix = "cardstock-media:"

    private func dragPayload(for paths: [String]) -> String {
        Self.dragPrefix + paths.joined(separator: "\n")
    }

    /// Moves dropped files and folders into `destination`.
    private func drop(_ payloads: [String], into destination: String) -> Bool {
        let paths = payloads.flatMap { text -> [String] in
            guard text.hasPrefix(Self.dragPrefix) else { return [] }
            return text.dropFirst(Self.dragPrefix.count).split(separator: "\n").map(String.init)
        }
        guard !paths.isEmpty else { return false }
        let folders = paths.filter { model.mediaFolders.contains($0) }
        for path in folders where !MediaLibrary.isInside(destination, path) {
            model.moveFolder(path, into: destination)
        }
        let files = model.files.filter { paths.contains($0.path) && $0.folder != destination }
        if !files.isEmpty { model.moveFiles(files, to: destination) }
        return true
    }

    /// Every folder, indented by depth, for Move To menus.
    @ViewBuilder
    private func moveMenu(excluding: @escaping (String) -> Bool, move: @escaping (String) -> Void) -> some View {
        Menu("Move To") {
            Button("Files (top level)") { move(MediaLibrary.folderName) }
                .disabled(excluding(MediaLibrary.folderName))
            if !model.mediaFolders.isEmpty { Divider() }
            ForEach(model.mediaFolders, id: \.self) { path in
                let depth = path.split(separator: "/").count - 2
                Button(String(repeating: "    ", count: max(depth, 0)) + MediaLibrary.name(of: path)) { move(path) }
                    .disabled(excluding(path))
            }
            Divider()
            Button("New Folder…") { startNewFolder() }
        }
    }

    // MARK: - Footer

    /// Stays at the bottom of the column, like the sidebar's New button.
    private var footer: some View {
        HStack {
            Button(action: chooseFiles) {
                Label("Add Files…", systemImage: "plus")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
            .help("Copy files into this folder. You can also drag files onto this page.")
            Button(action: startNewFolder) {
                Label("New Folder…", systemImage: "folder.badge.plus")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
            .help("Make a folder inside this one")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Files")
                    .font(.title2.bold())
                Text("Everything in your site's media folder, in folders you can make and move things between. Links to a file stay working when it moves.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 10) {
                SearchField(query: $query, prompt: "Search all files")
                FileFilterMenu(filter: $filter, sort: $sort)
            }
            if isBrowsing { pathBar }
            HStack(spacing: 10) {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if isFiltered {
                    Button(clearTitle) {
                        withAnimation(.snappy) {
                            filter = .all
                            query = ""
                        }
                    }
                    .buttonStyle(.link)
                    .font(.caption.weight(.medium))
                    .help("Show all files")
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var clearTitle: String { FileFilter.clearTitle(filter: filter, query: query) }

    /// True while a filter or search hides some files.
    private var isFiltered: Bool { filter != .all || !query.isEmpty }

    /// Counts and size for the files shown, so it follows the filter and search.
    private var summary: String {
        let files = shown
        let count = files.count
        let bytes = files.reduce(0) { $0 + $1.size }
        var text = "\(count) \(count == 1 ? "file" : "files") · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
        if isFiltered {
            text += " (of \(model.files.count))"
        }
        let unused = files.filter(\.usedIn.isEmpty).count
        if unused > 0 && filter != .unused { text += " · \(unused) not used on any page" }
        let selected = files.filter { selection.contains($0.id) }.count
        if selected > 1 { text += " · \(selected) selected" }
        return text
    }

    // MARK: - List

    private var selectionBinding: Binding<Set<MediaFile.ID>> {
        Binding(get: { model.selectedFileIDs }, set: { model.selectedFileIDs = $0 })
    }

    /// A standard macOS list: click selects, ⌘- and ⇧-click select more,
    /// double-click opens, and right-click acts on the selection.
    private var table: some View {
        List(selection: selectionBinding) {
            ForEach(subfolders, id: \.self) { path in
                folderRow(path)
                    .tag(Self.folderID(path))
                    .draggable(dragPayload(for: [path]))
                    .dropDestination(for: String.self) { items, _ in drop(items, into: path) }
            }
            ForEach(shown) { file in
                row(file)
                    .tag(file.id)
                    .draggable(dragPayload(for: selection.contains(file.id) ? files(selection).map(\.path) : [file.path])) {
                        dragPreview(file)
                    }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: MediaFile.ID.self) { ids in
            if let path = folders(ids).first, files(ids).isEmpty {
                folderMenu(path)
            } else {
                menu(for: files(ids))
            }
        } primaryAction: { ids in
            if let path = folders(ids).first {
                open(folder: path)
            } else {
                files(ids).forEach(open)
            }
        }
        .onDeleteCommand {
            let chosen = files(selection)
            if !chosen.isEmpty {
                pendingDelete = chosen
            } else if let path = folders(selection).first {
                pendingFolderDelete = path
            }
        }
        .onCopyCommand {
            // ⌘C copies the selected files' Markdown.
            let chosen = files(selection)
            guard !chosen.isEmpty else { return [] }
            let markdown = chosen.map(MediaLibrary.markdown(for:)).joined(separator: "\n\n")
            model.showToast(chosen.count == 1 ? "Copied. Paste it into a page or post." : "Copied \(chosen.count) files.")
            return [NSItemProvider(object: markdown as NSString)]
        }
    }

    /// Thumbnail, name, date and size, and where it's used.
    private func row(_ file: MediaFile) -> some View {
        HStack(spacing: 10) {
            FileThumbnail(file: file, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(rowDetails(file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                Text(file.usedIn.isEmpty ? "Not used" : "Used on " + ListFormatter.localizedString(byJoining: file.usedIn))
                    .font(.caption)
                    .foregroundStyle(file.usedIn.isEmpty ? Color.orange : Color.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .help(file.path)
    }

    private func rowDetails(_ file: MediaFile) -> String {
        let size = ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)
        var parts = [size]
        if !isBrowsing { parts.append(file.folder) }
        if file.added != .distantPast { parts.insert(file.added.formatted(date: .abbreviated, time: .omitted), at: 0) }
        if !file.tags.isEmpty { parts.append(file.tags.map { "#" + $0 }.joined(separator: " ")) }
        return parts.joined(separator: " · ")
    }

    private func files(_ ids: Set<MediaFile.ID>) -> [MediaFile] {
        shown.filter { ids.contains($0.id) }
    }

    /// List ids for folder rows, kept apart from file paths.
    private static func folderID(_ path: String) -> String { "folder:" + path }

    private func folders(_ ids: Set<MediaFile.ID>) -> [String] {
        subfolders.filter { ids.contains(Self.folderID($0)) }
    }

    private func open(folder path: String) {
        withAnimation(.snappy(duration: 0.2)) {
            model.filesFolder = path
            selection = []
        }
    }

    /// A folder: its icon, name and what's in it.
    private func folderRow(_ path: String) -> some View {
        let files = model.files.filter { MediaLibrary.isInside($0.path, path) }
        let folders = model.mediaFolders.filter { MediaLibrary.parent(of: $0) == path }.count
        var parts: [String] = []
        if files.isEmpty && folders == 0 { parts.append("Empty") }
        if !files.isEmpty {
            parts.append("\(files.count) \(files.count == 1 ? "file" : "files")")
            parts.append(ByteCountFormatter.string(fromByteCount: files.reduce(0) { $0 + $1.size }, countStyle: .file))
        }
        if folders > 0 { parts.append("\(folders) \(folders == 1 ? "folder" : "folders")") }
        return HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .font(.system(size: 26))
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(MediaLibrary.name(of: path)).lineLimit(1)
                Text(parts.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .help("/\(path)/ · Double-click to open. Drop files here to move them in.")
    }

    private func dragPreview(_ file: MediaFile) -> some View {
        let count = selection.contains(file.id) ? max(files(selection).count, 1) : 1
        return HStack(spacing: 8) {
            FileThumbnail(file: file, size: 28)
            Text(count == 1 ? file.name : "\(count) files").lineLimit(1)
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    /// Files › photos › 2026: each part opens that folder, and takes dropped files.
    private var pathBar: some View {
        let parts = folder.split(separator: "/").map(String.init)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(parts.indices, id: \.self) { i in
                    let path = parts[...i].joined(separator: "/")
                    if i > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    PathCrumb(title: i == 0 ? "Files" : parts[i], systemImage: i == 0 ? "photo.on.rectangle" : "folder",
                              isCurrent: path == folder) {
                        open(folder: path)
                    } onDrop: { items in
                        drop(items, into: path)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func folderMenu(_ path: String) -> some View {
        Button("Open") { open(folder: path) }
        Button("Rename…") { startRename(path) }
        moveMenu(excluding: { MediaLibrary.isInside($0, path) || $0 == MediaLibrary.parent(of: path) }) { destination in
            model.moveFolder(path, into: destination)
        }
        Divider()
        Button("Copy Address") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("/" + path + "/", forType: .string)
            model.showToast("Copied /\(path)/.")
        }
        Button("Show in Finder") {
            guard let root = model.site?.root else { return }
            NSWorkspace.shared.activateFileViewerSelecting([root.appending(path: path)])
        }
        Divider()
        Button("Move to Trash…", role: .destructive) { pendingFolderDelete = path }
    }

    @ViewBuilder
    private func menu(for files: [MediaFile]) -> some View {
        if !files.isEmpty {
            Button(files.count == 1 ? "Copy Markdown" : "Copy Markdown for \(files.count) Files") {
                model.copyMarkdown(for: files)
            }
            if files.count == 1, let file = files.first {
                Button("Copy Address") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("/" + file.path, forType: .string)
                    model.showToast("Copied /\(file.path).")
                }
            }
            moveMenu(excluding: { destination in files.allSatisfy { $0.folder == destination } }) { destination in
                model.moveFiles(files, to: destination)
            }
            Divider()
            Button("Open") { files.forEach(open) }
            Button("Show in Finder") {
                guard let root = model.site?.root else { return }
                NSWorkspace.shared.activateFileViewerSelecting(files.map { root.appending(path: $0.path) })
            }
        }
    }

    private func open(_ file: MediaFile) {
        guard let root = model.site?.root else { return }
        NSWorkspace.shared.open(root.appending(path: file.path))
    }

    // MARK: - Deleting

    private var deleteTitle: String {
        pendingDelete.count == 1
            ? "Move “\(pendingDelete[0].name)” to the Trash?"
            : "Move \(pendingDelete.count) files to the Trash?"
    }

    private var deleteMessage: String { Self.deleteMessage(for: pendingDelete) }

    /// What happens when these files go to the Trash, and which pages use them.
    static func deleteMessage(for pendingDelete: [MediaFile]) -> String {
        let used = pendingDelete.filter { !$0.usedIn.isEmpty }
        var text = pendingDelete.count == 1 ? "It goes to your Mac's Trash. " : "They go to your Mac's Trash. "
        text += "The next time you publish, \(pendingDelete.count == 1 ? "it's" : "they're") removed from GitHub and your live site too."
        if !used.isEmpty {
            let pages = Array(Set(used.flatMap(\.usedIn))).sorted()
            text = "\(used.count == 1 && pendingDelete.count == 1 ? "It's" : "Some are") used on \(ListFormatter.localizedString(byJoining: pages)), which will show \(used.count == 1 ? "it" : "them") as missing until you remove \(used.count == 1 ? "it" : "them") from the text. " + text
        }
        return text
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = "Add Files"
        panel.prompt = "Add"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        model.addFiles(panel.urls, to: folder)
    }
}

/// One part of the Files page's path bar: a folder to open, and to drop
/// files on. Lights up while something's dragged over it.
private struct PathCrumb: View {
    let title: String
    let systemImage: String
    let isCurrent: Bool
    let action: () -> Void
    let onDrop: ([String]) -> Bool
    @State private var isTargeted = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.callout.weight(isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? Color.primary : Color.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isTargeted ? Color.accentColor.opacity(0.18) : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .dropDestination(for: String.self) { items, _ in onDrop(items) } isTargeted: { isTargeted = $0 }
        .help(isCurrent ? "This folder" : "Open \(title). Drop files here to move them.")
    }
}

/// One file: thumbnail, name, date and size, its folder, and a pill saying
/// where it's used, with buttons on the right.
struct FileRow<Actions: View>: View {
    let file: MediaFile
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            FileThumbnail(file: file)

            VStack(alignment: .leading, spacing: 3) {
                Text(file.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(file.folder)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                usagePill
                    .padding(.top, 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(file.path)

            HStack(spacing: 8) {
                actions()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var details: String {
        let size = ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)
        var text = file.added == .distantPast ? size : "Added \(file.added.formatted(date: .abbreviated, time: .omitted)) · \(size)"
        if !file.tags.isEmpty { text += " · " + file.tags.map { "#" + $0 }.joined(separator: " ") }
        return text
    }

    private var usagePill: some View {
        let used = !file.usedIn.isEmpty
        let text = used ? "Used on " + ListFormatter.localizedString(byJoining: file.usedIn) : "Not used"
        let color: Color = used ? .green : .orange
        return Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
            .help(text)
    }
}

/// A round glass button with just an icon.
struct RoundIconButton: View {
    let symbol: String
    let label: String
    var color: Color = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .roundGlass(32)
        .accessibilityLabel(label)
    }
}

/// A small square preview: the image itself, or the file's icon.
struct FileThumbnail: View {
    @Environment(AppModel.self) private var model
    let file: MediaFile
    var size: CGFloat = 64

    var body: some View {
        Group {
            if let root = model.site?.root {
                if file.isImage {
                    // The inline version is smaller and quicker to show.
                    ImageThumbnail(url: root.appending(path: file.smallPath ?? file.path), size: size, fill: false)
                        // A new view after each image edit, so it loads the new picture.
                        .id("\(file.id)#\(model.mediaRevision)")
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: root.appending(path: file.path).path))
                        .resizable()
                        .scaledToFit()
                        .frame(width: size, height: size)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/// A search field in a glass capsule that fills the row.
struct SearchField: View {
    @Binding var query: String
    var prompt = "Search files"

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(prompt, text: $query)
                .textFieldStyle(.plain)
                .onExitCommand { query = "" }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

// MARK: - Shared by the Files page and the Insert from Files dialog

/// Which files to show.
enum FileFilter: String, CaseIterable, Hashable {
    case all = "All"
    case images = "Images"
    case videos = "Videos"
    case unused = "Not Used"

    /// The files matching a filter and search, in the chosen order.
    static func apply(_ files: [MediaFile], filter: FileFilter, sort: FileSort, query: String) -> [MediaFile] {
        files
            .filter { file in
                switch filter {
                case .all: true
                case .images: file.isImage
                case .videos: SiteRenderer.isVideoFile(file.path)
                case .unused: file.usedIn.isEmpty
                }
            }
            .filter { file in
                query.isEmpty || file.path.localizedCaseInsensitiveContains(query)
                    || file.tags.contains { $0.localizedCaseInsensitiveContains(query) }
            }
            .sorted { a, b in
                switch sort {
                case .newest: a.added != b.added ? a.added > b.added : a.name < b.name
                case .oldest: a.added != b.added ? a.added < b.added : a.name < b.name
                case .name: a.name.localizedStandardCompare(b.name) == .orderedAscending
                case .largest: a.size > b.size
                }
            }
    }

    /// Names what clearing resets: the search, the filter, or both.
    static func clearTitle(filter: FileFilter, query: String, default all: FileFilter = .all) -> String {
        switch (filter != all, !query.isEmpty) {
        case (true, true): "Clear Filters and Search"
        case (true, false): "Clear Filters"
        default: "Clear Search"
        }
    }
}

enum FileSort: String, CaseIterable {
    case newest = "Newest First"
    case oldest = "Oldest First"
    case name = "Name"
    case largest = "Largest First"
}

/// The round Show and Sort menu.
struct FileFilterMenu: View {
    @Binding var filter: FileFilter
    @Binding var sort: FileSort
    /// The filter that counts as "not filtering" (tints the button otherwise).
    var unfiltered: FileFilter = .all

    var body: some View {
        Menu {
            Section("Show") {
                Picker("Show", selection: $filter) {
                    ForEach(FileFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section("Sort By") {
                Picker("Sort By", selection: $sort) {
                    ForEach(FileSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 13, weight: .semibold))
                // Tinted while only some files are shown.
                .foregroundStyle(filter == unfiltered ? Color.primary : Color.accentColor)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .roundGlass(30)
        .help("Showing \(filter.rawValue) · \(sort.rawValue)")
    }
}
