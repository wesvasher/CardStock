import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if let site = model.site {
                SiteView(site: site)
            } else {
                WelcomeView()
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(message: toast)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.toast)
        .sheet(isPresented: $model.isShowingOpenFromGitHub) {
            OpenFromGitHubSheet()
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text("CardStock")
                .font(.largeTitle.bold())
            Text("Write pages, blog posts and product pages in Markdown.\nCardStock builds the site and publishes it through GitHub.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("New Site…") { SitePanels.newSite(model) }
                    .buttonStyle(.borderedProminent)
                Button("Open Site…") { SitePanels.openSite(model) }
                Button("Open from GitHub…") {
                    model.isShowingOpenFromGitHub = true
                }
            }
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SiteView: View {
    @Environment(AppModel.self) private var model
    let site: Site
    @AppStorage("showPreview") private var showPreview = true
    /// Configuration's preview of the theme page; hidden until asked for.
    @AppStorage("showConfigPreview") private var showConfigPreview = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selection) {
                Label("Start", systemImage: "square.grid.2x2")
                    .tag(SidebarSelection.start)
                Label("Status", systemImage: "stethoscope")
                    .badge(model.healthProblemCount)
                    .help(model.healthProblemCount == 0 ? "Site Health: all good"
                          : "Site Health: \(model.healthProblemCount) \(model.healthProblemCount == 1 ? "thing" : "things") to fix")
                    .tag(SidebarSelection.status)
                Label("Configuration", systemImage: "slider.horizontal.3")
                    .tag(SidebarSelection.configuration)
                HStack {
                    Label("Publishing", systemImage: "paperplane")
                    Spacer()
                    if model.publishIndicator == .publishing {
                        ProgressView()
                            .controlSize(.small)
                            .help("Publishing…")
                    } else if model.publishIndicator == .done || model.publishIndicator == .fading {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .opacity(model.publishIndicator == .fading ? 0 : 1)
                            .help("Published")
                    } else if let behind = model.syncStatus?.behind, behind > 0 {
                        // Purple seal: updates on GitHub from another Mac.
                        UpdateSeal(count: behind)
                            .help("\(behind) \(behind == 1 ? "update" : "updates") published from another Mac")
                    }
                }
                .badge(model.publishIndicator == nil ? model.syncStatus?.pendingCount ?? 0 : 0)
                .tag(SidebarSelection.publish)
                Label("Pages", systemImage: "doc.richtext")
                    .tag(SidebarSelection.pages)
                Label("Files", systemImage: "folder")
                    .tag(SidebarSelection.files)
                Label("Help Center", systemImage: "questionmark.circle")
                    .tag(SidebarSelection.help)
            }
            .navigationSplitViewColumnWidth(200)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                StatusBar()
            }
        } detail: {
            DetailView(site: site, showPreview: showPreview, showConfigPreview: showConfigPreview)
                // Views with a preview column bring it back automatically.
                .onChange(of: model.selection) { _, new in
                    if new?.hasPreviewColumn == true { showPreview = true }
                }
        }
        .navigationTitle(site.config.title)
        .navigationSubtitle(site.root.path(percentEncoded: false))
        .toolbar {
            ToolbarItem {
                Button { model.openWebsite() } label: {
                    Label("Open Website", systemImage: "arrow.up.right.square")
                }
                .help(model.websiteURL.map { "Open \($0.absoluteString) in your browser" }
                      ?? "Add a web address in Configuration → Site Details to open the site in your browser")
            }
            if model.project.github != nil {
                ToolbarItem {
                    Button {
                        // Publishes straight away; the commit gets an automatic description.
                        if model.isSignedIn {
                            Task { await model.publish(message: "") }
                        } else {
                            model.selection = .publish
                        }
                    } label: {
                        Label("Publish", systemImage: "icloud.and.arrow.up")
                    }
                    .disabled(model.isWorking)
                    .help(model.isSignedIn ? "Generate the flat HTML and send the site to GitHub" : "Sign in to GitHub to publish")
                }
            }
            ToolbarItem {
                let inConfiguration = model.selection == .configuration
                Toggle(isOn: inConfiguration
                       ? $showConfigPreview.animation(.smooth(duration: 0.35))
                       : $showPreview) {
                    Label("Preview", systemImage: "sidebar.right")
                }
                .disabled(!inConfiguration && model.selection?.hasPreviewColumn != true)
                .help(inConfiguration
                      ? "Show or hide a preview of the theme page"
                      : model.selection?.hasPreviewColumn == true
                      ? "Show or hide the preview"
                      : "This view uses the full width")
            }
        }
    }
}

/// Progress and results at the bottom of the sidebar.
struct StatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let message = model.workMessage ?? model.statusMessage {
            HStack(spacing: 6) {
                if model.isWorking { ProgressView().controlSize(.small) }
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
    }
}

/// The center column (editor or settings) plus the optional preview.
struct DetailView: View {
    @Environment(AppModel.self) private var model
    let site: Site
    let showPreview: Bool
    let showConfigPreview: Bool
    @AppStorage("previewDevice") private var device = PreviewDevice.fit
    @State private var navigator = PreviewNavigator()
    @State private var previewRevision = 0
    /// The editor's share of the width on the Pages view.
    @AppStorage("pagesSplit") private var pagesSplit = 0.5

    /// What Configuration's preview shows: a sample page for Layouts and
    /// Newsletter, else the Template page.
    private var configPreviewPath: String {
        switch model.configPage {
        case .layouts: SiteRenderer.layoutPreviewPath(model.previewLayoutID)
        case .newsletter: SiteRenderer.newsletterPreviewPath
        case .search: ContentItem.searchPath
        case .collections: model.previewCollectionPath
        case .tags: model.previewTagPath
        case .folders: model.previewFolderPath
        default: SiteRenderer.templatePagePath
        }
    }

    var body: some View {
        Group {
            if model.selection == .pages {
                pagesLayout
            } else if model.selection == .configuration {
                ConfigurationView(site: site, showPreview: showConfigPreview) {
                    devicePreview(path: configPreviewPath)
                }
            } else if model.selection == .files && showPreview {
                // Files: a fixed-width file list, then the selected file.
                HStack(spacing: 0) {
                    FilesView()
                        .frame(width: 380)
                        .frame(maxHeight: .infinity)
                    Divider()
                    FilePreviewPane()
                        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                splitLayout
            }
        }
        // Wait for a pause in typing before refreshing the preview.
        .task(id: model.revision) {
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled { previewRevision = model.revision }
        }
    }

    /// Pages: the page list (260 wide), then the editor and the preview,
    /// which start out sharing the rest of the width evenly.
    private var pagesLayout: some View {
        HStack(spacing: 0) {
            PagesView(site: site)
                .frame(width: 260)
                .frame(maxHeight: .infinity)
            Divider()
            if showPreview {
                ResizableSplit(fraction: $pagesSplit, minWidth: 360) {
                    pageEditor
                } trailing: {
                    devicePreview(path: model.selectedPage?.path ?? "/")
                }
            } else {
                pageEditor
            }
        }
    }

    @ViewBuilder
    private var pageEditor: some View {
        if let page = model.selectedPage {
            EditorView(item: page)
                .id(page.id)
        } else {
            ContentUnavailableView("No Page Selected", systemImage: "doc.text",
                                   description: Text("Choose a page on the left, or make a new one."))
        }
    }

    /// Everything else: the center column plus an optional right column.
    private var splitLayout: some View {
        HSplitView {
            Group {
                switch model.selection {
                case .start:
                    StartView(site: site)
                case .status:
                    StatusView(site: site)
                case .configuration:
                    EmptyView() // Shown above, with its own preview.
                case .publish:
                    PublishView(site: site)
                case .files:
                    FilesView()
                case .help:
                    HelpCenterView()
                case .item, .pages:
                    if let item = model.selectedItem {
                        EditorView(item: item)
                            .id(item.id)
                    } else {
                        nothingSelected
                    }
                case nil:
                    nothingSelected
                }
            }
            .frame(minWidth: 480, idealWidth: 520, maxWidth: .infinity, maxHeight: .infinity)

            if model.selection == .help {
                // Help articles use the preview's column, shown or not.
                HelpArticleView()
                    .frame(minWidth: 320, idealWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
            } else if showPreview && model.selection?.hasPreviewColumn == true {
                // The site preview, for pages being edited.
                devicePreview(path: model.selectedItem?.path ?? "/")
                    .frame(minWidth: 320, idealWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func devicePreview(path: String) -> some View {
        let preview = { (zoom: Double) in
            PreviewView(site: site, path: path, revision: previewRevision,
                        userAgent: device.userAgent, zoom: zoom, navigator: navigator)
        }
        return VStack(spacing: 0) {
            PreviewBar(device: $device, navigator: navigator)
            Divider()
            previewContent(preview)
        }
    }

    @ViewBuilder
    private func previewContent(_ preview: @escaping (Double) -> PreviewView) -> some View {
        Group {
            if let width = device.width {
                // Show the device's width, zooming out when it doesn't fit.
                GeometryReader { geo in
                    let available = max(geo.size.width - 32, 100)
                    let shown = min(width, available)
                    VStack(spacing: 6) {
                        Text(shown < width
                             ? "\(device.name) · \(Int(width)) px · \(Int((shown / width * 100).rounded()))%"
                             : "\(device.name) · \(Int(width)) px")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        preview(shown / width)
                            .frame(width: shown)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                    }
                    .padding(.vertical, 10)
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                .background(Color(nsColor: .underPageBackgroundColor))
            } else {
                preview(1)
            }
        }
    }

    private var nothingSelected: some View {
        ContentUnavailableView("Nothing Selected", systemImage: "doc.text",
                               description: Text("Choose a post, page or project, or make a new one."))
    }
}

struct NewItemSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var kind: ContentKind
    @State private var title = ""

    init(kind: ContentKind) {
        _kind = State(initialValue: kind)
    }

    private var config: SiteConfig { model.site?.config ?? SiteConfig() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New \(config.singularName(kind))")
                .font(.headline)
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)
            Picker("Type", selection: $kind) {
                PageKindOptions.options(config)
            }
            Text(config.summary(kind))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func create() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        model.newItem(kind, title: trimmed)
        dismiss()
    }
}

/// The page types to choose from in a Type menu: static page, each
/// collection's items and categories, and link menus.
enum PageKindOptions {
    @ViewBuilder
    static func options(_ config: SiteConfig, current: ContentKind? = nil) -> some View {
        Label("Static Page", systemImage: "doc.text").tag(ContentKind.page)
        ForEach(config.collections) { c in
            Section(c.name) {
                Label(c.itemName, systemImage: c.icon).tag(c.itemKind)
                if c.categories {
                    Label(c.categoryName, systemImage: "folder").tag(c.categoryKind)
                }
            }
        }
        // A page whose collection isn't in site.json keeps its type.
        if let current, current.collectionID != nil, !config.kinds.contains(current), !current.isMain {
            Section("Missing Collection") {
                Text("\(current.rawValue) (no such collection)").tag(current)
            }
        }
        Section {
            Label("Link Menu", systemImage: "link").tag(ContentKind.links)
        }
        if current != nil && current != .links {
            Section {
                Label("New Collection…", systemImage: "plus.rectangle.on.rectangle").tag(newCollection)
            }
        }
    }

    /// Stands for "New Collection…" in the page editor's menu: picking it
    /// opens the New Collection sheet instead of changing the type.
    static let newCollection = ContentKind.main("")
}

/// Open and save panels for sites.
@MainActor
enum SitePanels {
    static func openSite(_ model: AppModel) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Open Site"
        panel.message = "Choose a CardStock site folder (one with a site.json file)."
        if panel.runModal() == .OK, let url = panel.url {
            model.open(url)
        }
    }

    static func newSite(_ model: AppModel) {
        let panel = NSSavePanel()
        panel.title = "New Site"
        panel.prompt = "Create"
        panel.nameFieldLabel = "Site name:"
        panel.nameFieldStringValue = "My Site"
        panel.message = "CardStock creates a folder with a starter site in it."
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            model.createSite(at: url)
        }
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}

/// Two views side by side with a divider you can drag. `fraction` is the
/// leading view's share of the width; double-click the divider to split
/// evenly again.
struct ResizableSplit<Leading: View, Trailing: View>: View {
    @Binding var fraction: Double
    var minWidth: CGFloat = 300
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    @State private var dragStart: Double?

    var body: some View {
        GeometryReader { geo in
            let total = max(geo.size.width - 1, 1)
            let lower = min(minWidth / total, 0.5)
            let share = min(max(fraction, lower), 1 - lower)
            HStack(spacing: 0) {
                leading
                    .frame(width: total * share)
                    .frame(maxHeight: .infinity)
                Divider()
                    .overlay {
                        // A wider grab area than the 1-point line.
                        Color.clear
                            .frame(width: 9)
                            .contentShape(Rectangle())
                            .onHover { inside in
                                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                            }
                            .gesture(
                                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                    .onChanged { value in
                                        let start = dragStart ?? share
                                        dragStart = start
                                        fraction = min(max(start + value.translation.width / total, lower), 1 - lower)
                                    }
                                    .onEnded { _ in dragStart = nil })
                            .onTapGesture(count: 2) { fraction = 0.5 }
                    }
                    .zIndex(1)
                trailing
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
