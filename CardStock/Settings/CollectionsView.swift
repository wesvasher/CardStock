import SwiftUI

/// Configuration → Collections: the site's collections (Blog, Shop,
/// Portfolio, …), and the chosen one's settings: names, how its main page
/// and categories list items, what item pages show, and where items appear.
/// The preview shows the chosen collection's main page.
struct CollectionsView: View {
    @Environment(AppModel.self) private var model
    @State private var showAdd = false
    @State private var removing: ContentCollection?

    private var config: SiteConfig { model.site?.config ?? SiteConfig() }
    private var collections: [ContentCollection] { config.collections }
    /// The menu's order: by name.
    private var alphabetical: [ContentCollection] { ContentCollection.alphabetical(collections) }
    /// The one being edited: the one picked, else the first by name.
    private var selected: ContentCollection? {
        collections.first { $0.id == model.configCollectionID } ?? alphabetical.first
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    Picker("Collection", selection: Binding(
                        get: { selected?.id ?? "" },
                        set: { model.configCollectionID = $0 })) {
                        ForEach(alphabetical) { c in
                            Label(c.name, systemImage: c.icon).tag(c.id)
                        }
                    }
                    .disabled(collections.isEmpty)
                    Button("Add Collection…") { showAdd = true }
                }
                if let c = selected {
                    Text(details(c))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Collections")
            } footer: {
                caption("A collection is a section of your site: a main page that lists its items, a page for each item, and categories if you want them. Choose one to set it up.")
            }

            if let c = selected {
                CollectionSettings(collection: binding(c.id), search: searchBinding(c),
                                   onRemove: { removing = c })
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showAdd) { AddCollectionSheet() }
        .confirmationDialog("Delete the “\(removing?.name ?? "")” collection?",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            presenting: removing) { c in
            Button("Delete Collection", role: .destructive) { model.removeCollection(c.id) }
        } message: { c in
            Text(removeMessage(c))
        }
    }

    // MARK: - Picker

    /// "12 posts · /blog/ · 3 categories"
    private func details(_ c: ContentCollection) -> String {
        let items = model.site?.items(c.itemKind) ?? []
        let categories = c.categories ? model.site?.items(c.categoryKind).count ?? 0 : 0
        var text = "\(items.count) \((items.count == 1 ? c.itemName : c.itemsName).lowercased()) · \(c.mainPath)"
        if categories > 0 { text += " · \(categories) \(categories == 1 ? "category" : "categories")" }
        return text
    }

    // MARK: - Bindings

    private func binding(_ id: String) -> Binding<ContentCollection> {
        Binding(
            get: { config.collections.first { $0.id == id } ?? .fallback(id) },
            set: { value in
                var updated = config
                guard let i = updated.collections.firstIndex(where: { $0.id == id }) else { return }
                updated.collections[i] = value
                model.updateConfig(updated)
            })
    }

    /// Whether search finds the collection's items.
    private func searchBinding(_ c: ContentCollection) -> Binding<Bool> {
        Binding(
            get: { config.search.includes(c.itemKind) },
            set: { on in
                var updated = config
                updated.search.kinds.removeAll { $0 == c.itemType || $0 == c.categoryType }
                if on { updated.search.kinds += [c.itemType, c.categoryType] }
                model.updateConfig(updated)
            })
    }

    private func removeMessage(_ c: ContentCollection) -> String {
        let count = (model.site?.items ?? []).filter { $0.kind.collectionID == c.id }.count
        guard count > 0 else { return "It has no pages, so nothing else changes." }
        return "Its \(count) \(count == 1 ? "page becomes a static page" : "pages become static pages"). The main page keeps its address, \(c.mainPath); items and categories move to addresses of their own, like /name/, so links to them need updating."
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// One collection's settings, as Form sections.
private struct CollectionSettings: View {
    @Environment(AppModel.self) private var model
    @Binding var collection: ContentCollection
    @Binding var search: Bool
    let onRemove: () -> Void
    @State private var namingCategory = false
    @State private var categoryName = ""

    private var c: ContentCollection { collection }
    private var items: [ContentItem] { model.site?.items(c.itemKind) ?? [] }
    private var categories: [ContentItem] { model.site?.items(c.categoryKind) ?? [] }
    private var layouts: [PageLayout] { (model.site?.layouts ?? []).filter { $0.suits(c.itemKind) } }

    var body: some View {
        Section {
            TextField("Name", text: $collection.name, prompt: Text("Blog"))
            TextField("One item", text: $collection.itemName, prompt: Text("Post"))
            TextField("More than one", text: $collection.itemsName, prompt: Text("Posts"))
            Picker("Icon", selection: $collection.icon) {
                ForEach(iconChoices, id: \.self) { name in
                    Label(name, systemImage: name).labelStyle(.iconOnly).tag(name)
                }
            }
            LabeledContent("Addresses") {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Main page \(c.mainPath)")
                    Text("\(c.itemsName) \(ContentKind.item(c.id).path(for: "name"))")
                    if c.categories { Text("Categories \(ContentKind.category(c.id).path(for: "name"))") }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
            HStack {
                Button("Edit Main Page") { model.openMainPage(of: c) }
                Button("New \(c.itemName)…") { newItem() }
                Spacer()
            }
            .controlSize(.small)
        } header: {
            Text(c.name)
        } footer: {
            caption("The names show in CardStock and on your site, like “All \(c.itemsName.lowercased())”. The main page's title and text are a page you edit like any other. Addresses can't change once a collection is made.")
        }

        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Show items as")
                ChoiceCards(selection: $collection.listStyle, options: [
                    .init(value: .list, title: "List", systemImage: "list.bullet",
                          help: "Rows with the title, date and summary"),
                    .init(value: .cards, title: "Cards", systemImage: "square.grid.2x2",
                          help: "Cards with an image, title, price and summary"),
                    .init(value: .gallery, title: "Gallery", systemImage: "photo.on.rectangle",
                          help: "A grid of images with titles"),
                ])
            }
            if c.listStyle != .list {
                LabeledContent("Columns") {
                    Stepper("\(c.columns)", value: $collection.columns, in: 1...6)
                }
            }
            Picker("Order", selection: $collection.sort) {
                ForEach(ContentCollection.Sort.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if c.listStyle == .cards {
                Toggle("Images", isOn: $collection.listImages)
            }
            if c.dated {
                Toggle("Dates", isOn: $collection.listDates)
            }
            if c.listStyle != .gallery {
                Toggle("Summaries", isOn: $collection.listSummaries)
            }
            if c.categories {
                Toggle("Links to each category", isOn: $collection.listCategories)
            }
            TextField("When empty", text: $collection.emptyText, prompt: Text("No \(c.itemsName.lowercased()) yet."))
        } header: {
            Text("Main Page and Categories")
        } footer: {
            caption("How \(c.mainPath) and the category pages list \(c.itemsName.lowercased()). Images are each item's cover\(c.video ? ", or its YouTube thumbnail" : ""). On phones, grids show two columns or fewer.")
        }

        Section {
            Toggle("Items have a date", isOn: $collection.dated)
            if c.dated {
                Toggle("Show the date", isOn: $collection.showDate)
            }
            Toggle("Cover image", isOn: $collection.showCover)
            Toggle("Tags", isOn: $collection.showTags)
            if c.categories {
                Toggle("Categories", isOn: $collection.showCategories)
            }
            Toggle("Price and Buy button", isOn: $collection.selling)
            Toggle("Video", isOn: $collection.video)
            Toggle("Links to the previous and next \(c.itemName.lowercased())", isOn: $collection.prevNext)
            Picker("Layout for new \(c.itemsName.lowercased())", selection: $collection.itemLayout) {
                Text("Standard").tag("")
                ForEach(layouts) { Text($0.name).tag($0.id) }
                if !c.itemLayout.isEmpty && !layouts.contains(where: { $0.id == c.itemLayout }) {
                    Text("Missing: \(c.itemLayout)").tag(c.itemLayout)
                }
            }
        } header: {
            Text("\(c.itemName) Pages")
        } footer: {
            caption("What each \(c.itemName.lowercased()) page shows, and the fields its editor has. A date sorts \(c.itemsName.lowercased()) by time; Video plays a YouTube or Vimeo link or a video file at the top.")
        }

        Section {
            Toggle("Categories", isOn: $collection.categories)
            if c.categories {
                ForEach(categories) { category in
                    LabeledContent {
                        Button("Open") { model.selection = .item(category.id) }
                            .controlSize(.small)
                    } label: {
                        let count = items.filter { $0.categories.contains(category.slug) }.count
                        VStack(alignment: .leading, spacing: 1) {
                            Text(category.title + (category.isDraft ? " (draft)" : ""))
                            Text("\(count) \((count == 1 ? c.itemName : c.itemsName).lowercased()) · \(category.path)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                HStack {
                    Button("New Category…") { categoryName = ""; namingCategory = true }
                        .controlSize(.small)
                    Spacer()
                }
            }
        } header: {
            Text("Categories")
        } footer: {
            caption("Categories are pages that list some of the \(c.itemsName.lowercased()), like “Travel” in a blog. Put a \(c.itemName.lowercased()) in categories from its editor. Tags work across every collection; see Configuration → Tags.")
        }
        .alert("New \(c.categoryName)", isPresented: $namingCategory) {
            TextField("Name", text: $categoryName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let name = categoryName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { model.newItem(c.categoryKind, title: name, open: false) }
            }
        }

        Section {
            Toggle("List on the Home page", isOn: $collection.onHome)
            Toggle("Include in the RSS feed", isOn: $collection.inFeed)
            Toggle("Found by search", isOn: $search)
        } header: {
            Text("Elsewhere")
        } footer: {
            caption("Home lists the newest items of every collection turned on here. The feed (feed.xml) lets readers follow new \(c.itemsName.lowercased()).")
        }

        Section {
            HStack {
                Button(role: .destructive, action: onRemove) {
                    Label("Delete Collection…", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                Spacer()
            }
        } footer: {
            caption("Deletes the \(c.name) collection. You'll be asked to confirm. Its pages aren't deleted: they become static pages.")
        }
    }

    private var iconChoices: [String] {
        ContentCollection.iconChoices.contains(c.icon) ? ContentCollection.iconChoices : [c.icon] + ContentCollection.iconChoices
    }

    private func newItem() {
        model.newItem(c.itemKind, title: "New \(c.itemName)")
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// Makes a collection: pick a starting point, name it, and choose its address.
struct AddCollectionSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var preset = ContentCollection.Preset.portfolio
    @State private var name = "Portfolio"
    @State private var itemName = "Project"
    @State private var itemsName = "Projects"
    @State private var address = ""
    @State private var addressEdited = false

    private var site: Site? { model.site }
    private var id: String { addressEdited ? address : suggestedAddress }

    /// The name as an address, made unique.
    private var suggestedAddress: String {
        guard let site else { return Site.slugify(name) }
        let base = Site.slugify(name)
        var candidate = base
        var n = 2
        while ContentCollection.problem(withID: candidate, in: site) != nil && n < 50 {
            candidate = "\(base)-\(n)"
            n += 1
        }
        return candidate
    }

    private var problem: String? {
        guard let site else { return "Open a site first." }
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Type a name." }
        return ContentCollection.problem(withID: id, in: site)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Collection")
                .font(.headline)
            ChoiceCards(selection: $preset, options: ContentCollection.Preset.allCases.map {
                .init(value: $0, title: $0.title, systemImage: $0.systemImage, help: $0.summary)
            })
            Text(preset.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Form {
                TextField("Name", text: $name)
                TextField("One item", text: $itemName)
                TextField("More than one", text: $itemsName)
                TextField("Address", text: Binding(
                    get: { id },
                    set: { address = $0.lowercased(); addressEdited = true }))
                LabeledContent("Pages") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("/\(id)/ lists every \(itemName.lowercased())")
                        Text("/\(ContentCollection.itemFolder(id))/name/ for each one")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.columns)
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onChange(of: preset) { _, new in
            let names = ContentCollection(preset: new, id: "x")
            (name, itemName, itemsName) = (new == .custom ? "" : names.name, names.itemName, names.itemsName)
        }
    }

    private func create() {
        guard problem == nil else { return }
        var collection = ContentCollection(preset: preset, id: id, name: name.trimmingCharacters(in: .whitespaces))
        let one = itemName.trimmingCharacters(in: .whitespaces)
        let many = itemsName.trimmingCharacters(in: .whitespaces)
        if !one.isEmpty { collection.itemName = one }
        if !many.isEmpty { collection.itemsName = many }
        model.addCollection(collection)
        dismiss()
    }
}
