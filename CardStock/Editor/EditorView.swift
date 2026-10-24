import SwiftUI
import UniformTypeIdentifiers

/// Edits one post, page or project.
struct EditorView: View {
    @Environment(AppModel.self) private var model
    let item: ContentItem

    @State private var editor = MarkdownEditorController()
    @State private var pendingImages: PendingImages?
    @State private var showFilePicker = false
    @State private var confirmDelete = false

    var body: some View {
        form
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .confirmationDialog("Move “\(current.title)” to the Trash?", isPresented: $confirmDelete) {
            Button("Move to Trash", role: .destructive) { delete() }
        } message: {
            Text(deleteMessage)
        }
        .sheet(isPresented: $showFilePicker) {
            InsertFromFilesSheet { file in
                editor.insertBlocks([MediaLibrary.markdown(for: file)])
                model.showToast("Inserted \(file.name).")
            }
        }
        .sheet(item: $pendingImages) { pending in
            InsertImageSheet(pending: pending, item: current) { blocks, location in
                editor.insertBlocks(blocks, at: location)
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Title", text: binding(\.title))
                    .font(.title.bold())
                    .textFieldStyle(.plain)

                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 8) {
                    let kind = current.kind
                    let collection = config.collection(for: kind)
                    GridRow {
                        label("Type")
                        if current.isFixedPage {
                            Text(current.isHome ? "Home page"
                                 : current.isNotFoundPage ? "Page for broken links"
                                 : current.isSearchPage ? "Search page: a search field and results, below this text"
                                 : "Template: every part of your style, for the preview")
                                .foregroundStyle(.secondary)
                        } else if kind.isMain, let collection {
                            HStack(spacing: 8) {
                                Label("\(collection.name) main page", systemImage: "list.bullet.rectangle")
                                    .foregroundStyle(.secondary)
                                Button("Collection Settings…") { showCollection(collection) }
                                    .buttonStyle(.link)
                                    .controlSize(.small)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 3) {
                                Picker("Type", selection: kindBinding) {
                                    PageKindOptions.options(config, current: kind)
                                }
                                .labelsHidden()
                                .fixedSize()
                                // Link menus are explained in the Help Center instead.
                                if kind != .links {
                                    Text(config.summary(kind))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    if kind != .links && !current.isTemplatePage && !current.isSearchPage {
                        GridRow {
                            label("Layout")
                            LayoutPicker(item: current, layout: field("layout"))
                        }
                    }
                    // Addresses are set by CardStock (a page's type and
                    // collection), so there's nothing to edit here.
                    if kind != .links && !current.isHome && !current.isTemplatePage && !current.isSearchPage && !kind.isMain {
                        GridRow {
                            label("Status")
                            Toggle("Draft", isOn: binding(\.isDraft))
                                .help("Drafts show in the preview but aren't published")
                        }
                    }
                    if kind.isItem, let collection {
                        if collection.dated {
                            GridRow {
                                label("Date")
                                DatePicker("Date", selection: dateBinding, displayedComponents: .date)
                                    .labelsHidden()
                                    .fixedSize()
                            }
                        }
                        if collection.selling {
                            GridRow {
                                label("Price")
                                TextField("$24.00", text: field("price"))
                            }
                            GridRow {
                                label("Buy link")
                                TextField("Checkout link from Stripe, Gumroad, Etsy, Shopify or PayPal", text: field("buy"))
                            }
                            GridRow {
                                label("Button")
                                TextField("Buy Now", text: field("buyLabel"))
                            }
                        }
                        if collection.video {
                            GridRow {
                                label("Video")
                                TextField("YouTube or Vimeo link, or a video file like /media/files/clip.mp4", text: field("video"))
                            }
                        }
                        if collection.categories {
                            GridRow {
                                label("Categories")
                                CategoryPicker(item: current, collection: collection)
                            }
                        }
                    }
                    if kind.isCategory || kind.isMain, let collection {
                        GridRow {
                            label("Lists")
                            let items = model.site?.items(collection.itemKind) ?? []
                            let count = kind.isMain ? items.count : items.filter { $0.categories.contains(current.slug) }.count
                            let noun = (count == 1 ? collection.itemName : collection.itemsName).lowercased()
                            Text(kind.isMain
                                 ? "Every \(collection.itemName.lowercased()) in \(collection.name) (\(count) \(noun)), \(collection.sort.title.lowercased())."
                                 : "\(count) \(noun) in this category. Choose categories on each \(collection.itemName.lowercased()).")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if kind != .links && !current.isTemplatePage {
                        GridRow {
                            label("Summary")
                            TextField("Short description for lists and search engines", text: field("summary"), axis: .vertical)
                                .lineLimit(1...3)
                        }
                        GridRow {
                            label("Cover")
                            TextField("/media/image.jpg", text: field("cover"))
                        }
                    }
                    // Every page can have tags.
                    GridRow {
                        label("Tags")
                        TagEditor(tags: binding(\.tags), suggestions: model.site?.tagIndex().map(\.name) ?? [])
                    }
                }
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
            }
            .padding(16)

            Divider()

            FormattingBar(editor: editor, onUploadImage: chooseImages, onChooseFromFiles: { showFilePicker = true })
                .padding(.horizontal, 10)
                .padding(.vertical, 5)

            Divider()

            MarkdownEditor(text: binding(\.body), controller: editor) { urls, index in
                pendingImages = PendingImages(urls: urls, location: index)
            }
            .padding(.horizontal, 4)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Footer

    /// Stays at the bottom of the editor: deleting, or why this page can't be.
    private var footer: some View {
        HStack {
            if current.canBeDeleted {
                Button { confirmDelete = true } label: {
                    Label("Move to Trash…", systemImage: "trash")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .help("Move this \(config.singularName(current.kind).lowercased()) to your Mac's Trash")
            } else {
                Label(current.isHome
                      ? "Every site needs a Home page, so it can't be deleted."
                      : current.isNotFoundPage
                      ? "Every site needs a page for broken links, so it can't be deleted."
                      : current.isSearchPage
                      ? "The Search page shows search results, so it can't be deleted. Turn search off in Configuration → Search."
                      : current.kind.isMain
                      ? "A collection's main page goes when you delete the collection in Configuration → Collections."
                      : "The Template page shows your style in the preview, so it can't be deleted.",
                      systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var deleteMessage: String {
        var text = "Its file goes to your Mac's Trash. The next time you publish, it's removed from your live site. Its images stay in Files."
        if model.site?.config.menuLinks.contains(where: { $0.url == current.path }) == true {
            text = "It's in your site's top bar, so remove that link in Configuration → Top Navigation Bar too. " + text
        }
        return text
    }

    private func delete() {
        model.delete(item.id)
    }

    /// Insert Image…: pick image files, then insert them at the cursor.
    private func chooseImages() {
        let panel = NSOpenPanel()
        panel.title = "Insert Image"
        panel.prompt = "Insert"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = ImageImporter.supportedExtensions.compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        pendingImages = PendingImages(urls: panel.urls, location: editor.cursorLocation)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    // MARK: - Bindings

    private var config: SiteConfig { model.site?.config ?? SiteConfig() }

    private func showCollection(_ collection: ContentCollection) {
        model.configCollectionID = collection.id
        model.showConfiguration(.collections)
    }

    /// The page's type. Becoming an item of a dated collection gives it
    /// today's date when it has none.
    private var kindBinding: Binding<ContentKind> {
        Binding(
            get: { current.kind },
            set: { newValue in
                var updated = current
                updated.kind = newValue
                if newValue.isItem, config.collection(for: newValue)?.dated == true, updated.date.isEmpty {
                    updated.date = Self.isoDate.string(from: .now)
                }
                model.update(updated)
            })
    }

    /// Reads from the model's current copy of the item, so edits never
    /// overwrite each other.
    private var current: ContentItem {
        model.site?.items.first { $0.id == item.id } ?? item
    }

    private func binding<T>(_ keyPath: WritableKeyPath<ContentItem, T>) -> Binding<T> {
        Binding(
            get: { current[keyPath: keyPath] },
            set: { newValue in
                var updated = current
                updated[keyPath: keyPath] = newValue
                model.update(updated)
            })
    }

    private func field(_ key: String) -> Binding<String> {
        Binding(
            get: { current.frontMatter.string(key) ?? "" },
            set: { newValue in
                var updated = current
                updated.frontMatter.setString(key, newValue)
                model.update(updated)
            })
    }

    private static let isoDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var dateBinding: Binding<Date> {
        Binding(
            get: { Self.isoDate.date(from: current.date) ?? .now },
            set: { newValue in
                var updated = current
                updated.date = Self.isoDate.string(from: newValue)
                model.update(updated)
            })
    }
}

/// Buttons above the editor that insert Markdown for the selection.
private struct FormattingBar: View {
    let editor: MarkdownEditorController
    let onUploadImage: () -> Void
    let onChooseFromFiles: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Menu {
                Button("Large Heading") { editor.heading(2) }
                Button("Medium Heading") { editor.heading(3) }
                Button("Small Heading") { editor.heading(4) }
                Divider()
                Button("Normal Text") { editor.heading(0) }
                Button("Fine Print") { editor.finePrint() }
            } label: {
                Image(systemName: "textformat.size")
            }
            .menuIndicator(.visible)
            .fixedSize()
            .help("Text style: headings, normal text or fine print (for captions, credits and notes)")

            separator
            tool("bold", "Bold (⌘B)", editor.bold)
            tool("italic", "Italic (⌘I)", editor.italic)
            tool("strikethrough", "Strikethrough", editor.strikethrough)
            tool("chevron.left.forwardslash.chevron.right", "Code", editor.code)
            separator
            tool("link", "Link (⌘K)", editor.link)
            tool("list.bullet", "Bulleted list", { editor.lines(.bullet) })
            tool("list.number", "Numbered list", { editor.lines(.numbered) })
            tool("text.quote", "Quote", { editor.lines(.quote) })
            tool("minus", "Divider line", editor.divider)
            tool("rectangle.split.1x2", "Section break: in layouts with more than one area, the text after it goes in the next area", editor.sectionBreak)
            tool("envelope", "Mailing list sign-up box: set it up in Configuration → Mailing List", editor.newsletter)
            tool("magnifyingglass", "Search box: searching from it opens the Search page", editor.searchBox)
            separator
            Menu {
                Button("Choose from Site Files…", systemImage: "photo.on.rectangle", action: onChooseFromFiles)
                Button("Upload from Mac…", systemImage: "square.and.arrow.up", action: onUploadImage)
            } label: {
                Image(systemName: "photo.badge.plus")
            }
            .menuIndicator(.visible)
            .fixedSize()
            .help("Insert an image at the cursor. You can also drag or paste images into the text.")
            Spacer(minLength: 0)
        }
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
        .controlSize(.regular)
    }

    private func tool(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .help(help)
        .accessibilityLabel(help)
    }

    private var separator: some View {
        Divider().frame(height: 16).padding(.horizontal, 4)
    }
}

/// The categories an item is in: a menu with a checkbox for each of its
/// collection's category pages, and a way to make a new one.
private struct CategoryPicker: View {
    @Environment(AppModel.self) private var model
    let item: ContentItem
    let collection: ContentCollection
    @State private var isNaming = false
    @State private var newName = ""

    private var categories: [ContentItem] { model.site?.items(collection.categoryKind) ?? [] }

    private var summary: String {
        let names = item.categories.compactMap { slug in categories.first { $0.slug == slug }?.title }
        return names.isEmpty ? "None" : ListFormatter.localizedString(byJoining: names)
    }

    var body: some View {
        Menu {
            ForEach(categories) { category in
                Toggle(category.title, isOn: Binding(
                    get: { item.categories.contains(category.slug) },
                    set: { on in
                        var updated = model.site?.items.first { $0.id == item.id } ?? item
                        updated.categories.removeAll { $0 == category.slug }
                        if on { updated.categories.append(category.slug) }
                        model.update(updated)
                    }))
            }
            if !categories.isEmpty { Divider() }
            Button("New \(collection.categoryName)…") { newName = ""; isNaming = true }
        } label: {
            Text(summary)
        }
        .fixedSize()
        .alert("New \(collection.categoryName)", isPresented: $isNaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Create") { create() }
        } message: {
            Text("This \(collection.itemName.lowercased()) goes in it. Write the category page's text later in Pages.")
        }
    }

    /// Makes the category page (without leaving this page) and adds this item to it.
    private func create() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let before = Set(model.site?.items.map(\.id) ?? [])
        guard model.newItem(collection.categoryKind, title: name, open: false) != nil,
              let category = model.site?.items.first(where: { !before.contains($0.id) })
        else { return }
        var updated = model.site?.items.first { $0.id == item.id } ?? item
        updated.categories.append(category.slug)
        model.update(updated)
    }
}

/// A page's layout as an accordion: closed, it shows the current layout
/// (Standard is the type's own design); open, every layout that suits the
/// page's type is a card, and picking one animates the selection.
private struct LayoutPicker: View {
    @Environment(AppModel.self) private var model
    let item: ContentItem
    @Binding var layout: String
    @State private var isOpen = false

    private var layouts: [PageLayout] { model.site?.layouts ?? [] }
    private var chosen: PageLayout? { layouts.first { $0.id == item.layout } }
    private var isMissing: Bool { !item.layout.isEmpty && chosen == nil }

    private var currentName: String {
        if isMissing { return "Missing: \(item.layout)" }
        return chosen?.name ?? "Standard"
    }
    private var currentImage: String {
        if isMissing { return "exclamationmark.triangle" }
        return chosen?.systemImage ?? PageLayout.standardImage
    }

    private var options: [ChoiceCards<String>.Option] {
        var list: [ChoiceCards<String>.Option] = [
            .init(value: "", title: "Standard", systemImage: PageLayout.standardImage,
                  help: "The page type's own design"),
        ]
        for layout in layouts where layout.suits(item.kind) || layout.id == item.layout {
            list.append(.init(value: layout.id, title: layout.name, systemImage: layout.systemImage,
                              help: layout.description))
        }
        if isMissing {
            list.append(.init(value: item.layout, title: "Missing", systemImage: "exclamationmark.triangle",
                              help: "There's no “\(item.layout)” in theme/layouts"))
        }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.snappy(duration: 0.3)) { isOpen.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isOpen ? 90 : 0))
                        Image(systemName: currentImage)
                            .foregroundStyle(isMissing ? AnyShapeStyle(.orange) : AnyShapeStyle(.tint))
                            .frame(width: 18)
                            .contentTransition(.symbolEffect(.replace))
                        Text(currentName)
                            .contentTransition(.opacity)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isOpen ? "Hide the layouts" : "Show the layouts")
                .accessibilityLabel("Layout: \(currentName)")
                .accessibilityHint(isOpen ? "Hides the layouts" : "Shows the layouts")
                Spacer(minLength: 0)
                Button("Layouts…") { model.showConfiguration(.layouts) }
                    .buttonStyle(.link)
                    .controlSize(.small)
            }
            if isOpen {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 140), spacing: 10)],
                          alignment: .leading, spacing: 10) {
                    ForEach(options, id: \.value) { option in
                        ChoiceCard(title: option.title, systemImage: option.systemImage, help: option.help,
                                   isSelected: layout == option.value) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                layout = option.value
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .clipped()
    }

    private var note: String? {
        if !item.layout.isEmpty && chosen == nil {
            return "There's no “\(item.layout)” in theme/layouts, so this page uses Standard."
        }
        guard let chosen else { return nil }
        guard chosen.areas.count > 1 else { return chosen.description.isEmpty ? nil : chosen.description }
        let used = PageLayout.sections(of: item.body).count
        return "Areas: \(chosen.areas.joined(separator: ", ")). Section breaks move text to the next area"
            + (used > 1 ? " (this page has \(used) sections)." : "; without them, it all goes in \(chosen.mainArea).")
    }
}
