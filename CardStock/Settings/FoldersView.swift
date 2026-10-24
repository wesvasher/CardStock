import AppKit
import SwiftUI

/// Configuration → Folders: the folders in your site's addresses. CardStock
/// makes some itself (one per collection, plus /pages/, /tags/, /media/ and
/// /assets/), which are locked. Your own folders are short addresses, like
/// /subscribe/, that show one of your pages; the page keeps its own address.
struct FoldersView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("showConfigPreview") private var showPreview = false
    @State private var showNew = false
    @State private var removing: Folder?

    private var config: SiteConfig { model.site?.config ?? SiteConfig() }

    var body: some View {
        Form {
            Section {
                if config.folders.isEmpty {
                    Text("No folders of your own yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(config.folders) { folder in customRow(folder) }
                HStack {
                    Button("New Folder…") { showNew = true }
                    Spacer()
                }
            } header: {
                Text("Your Folders")
            } footer: {
                caption("A folder you make is a short address for one of your pages: \(address("/subscribe/")) can show the page at /pages/subscribe/. The page keeps its own address too, and search engines are told that's the original. Deleting a folder only removes the short address; the page stays where it is.")
            }

            Section {
                ForEach(config.systemFolders) { folder in systemRow(folder) }
            } header: {
                Text("Made by CardStock")
            } footer: {
                caption("CardStock makes these folders and uses them itself, so they can't be deleted or used for anything else. Making a collection adds its folder; deleting the collection removes it.")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showNew) { NewFolderSheet() }
        .confirmationDialog("Delete the \(removing?.path ?? "") folder?",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            presenting: removing) { folder in
            Button("Delete Folder", role: .destructive) { delete(folder) }
        } message: { folder in
            Text("\(address(folder.path)) stops working. The page it shows stays at its own address\(target(folder).map { ", \($0.path)" } ?? "").")
        }
    }

    // MARK: - Rows

    private func customRow(_ folder: Folder) -> some View {
        let page = target(folder)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .foregroundStyle(.tint)
                    .frame(width: 20)
                Text(folder.path)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Picker("Shows", selection: Binding(
                    get: { folder.page },
                    set: { setPage($0, for: folder) })) {
                    if page == nil { Text("Missing page").tag(folder.page) }
                    FolderPageOptions.options(model.site)
                }
                .labelsHidden()
                .fixedSize()
                Spacer(minLength: 0)
                Button {
                    model.previewFolderName = folder.name
                    if !showPreview { withAnimation(.smooth(duration: 0.35)) { showPreview = true } }
                } label: {
                    Image(systemName: "eye")
                }
                .buttonStyle(.borderless)
                .help("Preview \(folder.path)")
                Button {
                    removing = folder
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .help("Delete this folder (the page stays)")
            }
            Text(note(folder, page))
                .font(.caption)
                .foregroundStyle(page == nil || page?.isDraft == true ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .padding(.leading, 30)
        }
        .padding(.vertical, 2)
    }

    private func systemRow(_ folder: Folder.System) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.path)
                    .font(.body.monospaced())
                Text(folder.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text("Made by CardStock")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .help("Made by CardStock. It can't be deleted or used for anything else.")
    }

    // MARK: - Helpers

    /// The page a folder shows, or a collection's main page.
    private func target(_ folder: Folder) -> ContentItem? {
        guard let site = model.site else { return nil }
        if let item = site.items.first(where: { $0.slug == folder.page }) { return item }
        if let c = site.config.collection(folder.page) {
            return ContentItem(fileURL: site.root.appending(path: "pages/\(c.id).md"),
                               text: "---\ntitle: \(c.name)\ntype: \(ContentKind.mainType)\n---\n")
        }
        return nil
    }

    private func note(_ folder: Folder, _ page: ContentItem?) -> String {
        guard let page else { return "The page it showed isn't there anymore, so \(folder.path) isn't published. Choose another page." }
        if page.isDraft { return "“\(page.title)” is a draft, so \(folder.path) is published once the page is." }
        return "\(address(folder.path)) shows “\(page.title)”, which is also at \(page.path)."
    }

    /// An address with the site's web address in front, when there is one.
    private func address(_ path: String) -> String {
        let base = config.baseURL
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        return base.isEmpty ? path : base + path
    }

    private func setPage(_ slug: String, for folder: Folder) {
        var updated = config
        guard let i = updated.folders.firstIndex(where: { $0.name == folder.name }) else { return }
        updated.folders[i].page = slug
        model.updateConfig(updated)
    }

    private func delete(_ folder: Folder) {
        var updated = config
        updated.folders.removeAll { $0.name == folder.name }
        model.updateConfig(updated)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// The pages a folder can show: static pages, then each collection's main
/// page, items and categories. Tags are page file names (a collection's main
/// page is its id).
enum FolderPageOptions {
    @ViewBuilder
    static func options(_ site: Site?) -> some View {
        if let site {
            let pages = site.items(.page).filter { !$0.isTemplatePage }
            Section("Pages") {
                ForEach(pages) { page in
                    Text(label(page)).tag(page.slug)
                }
            }
            ForEach(site.config.collections) { c in
                Section(c.name) {
                    Text("\(site.mainPage(of: c)?.title ?? c.name) (main page)").tag(c.id)
                    ForEach(site.items(c.itemKind) + site.items(c.categoryKind)) { page in
                        Text(label(page)).tag(page.slug)
                    }
                }
            }
        }
    }

    private static func label(_ page: ContentItem) -> String {
        page.isDraft ? "\(page.title) (draft)" : page.title
    }
}

/// Makes a folder: its name and the page it shows.
struct NewFolderSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var page = ""

    private var config: SiteConfig { model.site?.config ?? SiteConfig() }
    /// What's typed, as a folder name ("/Subscribe/" → "subscribe").
    private var cleaned: String {
        name.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).lowercased()
    }
    private var problem: String? {
        if let p = config.folderProblem(cleaned) { return p }
        return page.isEmpty ? "Choose the page it shows." : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Folder")
                .font(.headline)
            Text("A short address that shows one of your pages. The page keeps its own address too.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Form {
                LabeledContent("Folder") {
                    HStack(spacing: 2) {
                        Text("/").foregroundStyle(.secondary)
                        TextField("subscribe", text: $name)
                            .labelsHidden()
                        Text("/").foregroundStyle(.secondary)
                    }
                    .font(.body.monospaced())
                }
                Picker("Shows", selection: $page) {
                    Text("Choose a Page").tag("")
                    FolderPageOptions.options(model.site)
                }
            }
            .formStyle(.columns)
            .onChange(of: cleaned) { _, new in
                // A page with the same name is the likely choice.
                if page.isEmpty, model.site?.items.contains(where: { $0.slug == new && !$0.isLinkMenu }) == true {
                    page = new
                }
            }
            if !cleaned.isEmpty || !page.isEmpty, let problem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
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
        .frame(width: 440)
    }

    private func create() {
        guard problem == nil else { return }
        var updated = config
        updated.folders.append(Folder(name: cleaned, page: page))
        model.updateConfig(updated)
        model.previewFolderName = cleaned
        dismiss()
    }
}
