import SwiftUI
import UniformTypeIdentifiers

/// Picks a file from the site's Files to insert into the text. Clicking a
/// file (or its Insert button) inserts it and closes the dialog.
struct InsertFromFilesSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var title = "Insert from Files"
    var message = "Click a file to insert it where your cursor is."
    var actionTitle = "Insert"
    /// Shows "Choose from Mac…", which copies an image into Files and uses it.
    var allowsMacFiles = false
    let onInsert: (MediaFile) -> Void

    @State private var query = ""
    // The image button opened this, so start with images.
    @State private var filter = FileFilter.images
    @State private var sort = FileSort.newest
    @State private var hovered: MediaFile.ID?

    private var shown: [MediaFile] {
        FileFilter.apply(model.files, filter: filter, sort: sort, query: query)
    }

    private var isFiltered: Bool { filter != .images || !query.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.bold())
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    SearchField(query: $query)
                    FileFilterMenu(filter: $filter, sort: $sort, unfiltered: .images)
                }
                HStack(spacing: 10) {
                    let count = shown.count
                    Text("\(count) \(count == 1 ? "file" : "files")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if isFiltered {
                        Button(FileFilter.clearTitle(filter: filter, query: query, default: .images)) {
                            withAnimation(.snappy) {
                                filter = .images
                                query = ""
                            }
                        }
                        .buttonStyle(.link)
                        .font(.caption.weight(.medium))
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(20)

            Divider()

            if model.files.isEmpty {
                ContentUnavailableView("No Files Yet", systemImage: "folder",
                                       description: Text("Add images with Upload from Mac, or on the Files page."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shown.isEmpty {
                ContentUnavailableView("No Matching Files", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(shown) { file in
                            card(file)
                        }
                    }
                    .padding(16)
                }
            }

            Divider()
            HStack {
                if allowsMacFiles {
                    Button("Choose from Mac…", action: chooseFromMac)
                        .help("Copy an image from your Mac into your site's Files and use it")
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 580, height: 620)
        .onAppear { model.refreshFiles() }
    }

    private func card(_ file: MediaFile) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        let isHovered = hovered == file.id
        return FileRow(file: file) {
            Button {
                insert(file)
            } label: {
                Label(actionTitle, systemImage: "plus")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .padding(10)
        .background(shape.fill(isHovered ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05)))
        .contentShape(shape)
        .onHover { hovered = $0 ? file.id : (hovered == file.id ? nil : hovered) }
        .onTapGesture { insert(file) }
        .help("\(actionTitle) \(file.name)")
    }

    /// Copies an image from the Mac into media/files, then uses it.
    private func chooseFromMac() {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = actionTitle
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url,
              let file = model.addFiles([url]).first
        else { return }
        insert(file)
    }

    private func insert(_ file: MediaFile) {
        dismiss()
        onInsert(file)
    }
}
