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

    private var shown: [MediaFile] {
        FileFilter.apply(model.files, filter: filter, sort: sort, query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.files.isEmpty {
                Divider()
                ContentUnavailableView {
                    Label("No Files Yet", systemImage: "folder")
                } description: {
                    Text("Images you add to pages appear here. You can also drag files here, or into the site's media folder in Finder.")
                } actions: {
                    Button("Add Files…", action: chooseFiles)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shown.isEmpty {
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
            model.addFiles(files)
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
            .help("Copy files into the site's media/files folder. You can also drag files onto this page.")
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
                Text("Everything in your site's media folder. Copy a file's Markdown and paste it into a page to use it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 10) {
                SearchField(query: $query)
                FileFilterMenu(filter: $filter, sort: $sort)
            }
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
        List(shown, selection: selectionBinding) { file in
            row(file)
                .tag(file.id)
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: MediaFile.ID.self) { ids in
            menu(for: files(ids))
        } primaryAction: { ids in
            files(ids).forEach(open)
        }
        .onDeleteCommand { pendingDelete = files(selection) }
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
        var parts = [size, file.folder]
        if file.added != .distantPast { parts.insert(file.added.formatted(date: .abbreviated, time: .omitted), at: 0) }
        return parts.joined(separator: " · ")
    }

    private func files(_ ids: Set<MediaFile.ID>) -> [MediaFile] {
        shown.filter { ids.contains($0.id) }
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
        model.addFiles(panel.urls)
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
        guard file.added != .distantPast else { return size }
        return "Added \(file.added.formatted(date: .abbreviated, time: .omitted)) · \(size)"
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
    case unused = "Not Used"

    /// The files matching a filter and search, in the chosen order.
    static func apply(_ files: [MediaFile], filter: FileFilter, sort: FileSort, query: String) -> [MediaFile] {
        files
            .filter { file in
                switch filter {
                case .all: true
                case .images: file.isImage
                case .unused: file.usedIn.isEmpty
                }
            }
            .filter { query.isEmpty || $0.path.localizedCaseInsensitiveContains(query) }
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
