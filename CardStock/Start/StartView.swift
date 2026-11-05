import AppKit
import SwiftUI

/// What you see when a site opens: tiles for the common things to do, and
/// recently edited pages and added files to pick up where you left off.
/// The preview is hidden here.
struct StartView: View {
    @Environment(AppModel.self) private var model
    let site: Site
    @State private var newItemKind: ContentKind?

    private var current: Site { model.site ?? site }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                // The two most common things to do, big.
                HStack(spacing: 14) {
                    ForEach(heroTiles) { tile in
                        StartTile(tile: tile, isLarge: true)
                    }
                }
                // Everything else, all the same size.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
                    ForEach(tiles) { tile in
                        StartTile(tile: tile)
                    }
                }
                recent
                dashboard
            }
            .padding(28)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $newItemKind) { kind in
            NewItemSheet(kind: kind)
        }
        .onAppear {
            model.refreshActivity()
            model.refreshFiles()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(current.config.title)
                .font(.largeTitle.bold())
            Text(statusLine)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var statusLine: String {
        let posts = current.items(.post)
        let drafts = posts.filter(\.isDraft).count
        var parts = ["\(posts.count) \(posts.count == 1 ? "post" : "posts")",
                     "\(current.items(.page).count) pages"]
        if drafts > 0 { parts.append("\(drafts) \(drafts == 1 ? "draft" : "drafts")") }
        if let pending = model.syncStatus?.pendingCount, pending > 0 {
            parts.append("\(pending) \(pending == 1 ? "change" : "changes") to publish")
        } else if let last = model.lastPublished {
            parts.append("published \(last.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Tiles

    private var heroTiles: [StartTile.Tile] {
        [
            .init(title: "New Post", detail: "Write a blog post. It stays a draft until you're ready to share it.",
                  icon: "square.and.pencil", color: .blue) { newItemKind = .post },
            .init(title: "New Page", detail: "Add an About, Contact or any other standalone page.",
                  icon: "doc.badge.plus", color: .teal) { newItemKind = .page },
        ]
    }

    private var tiles: [StartTile.Tile] {
        var list: [StartTile.Tile] = []
        if let home = current.home {
            list.append(.init(title: "Edit Home Page", detail: "Change what visitors see first.",
                              icon: "house.fill", color: .orange) { model.selection = .item(home.id) })
        }
        list += [
            .init(title: "Browse Pages", detail: "Find and edit any of your pages.",
                  icon: "doc.richtext", color: .indigo) { model.selection = .pages },
            .init(title: "Add Images & Files", detail: "See every file in your site and add new ones.",
                  icon: "photo.on.rectangle.angled", color: .pink) { model.selection = .files },
            .init(title: "Change the Look", detail: "Fonts, colors, corners and width.",
                  icon: "paintpalette.fill", color: .purple) { model.showConfiguration(.templates) },
        ]
        return list
    }

    // MARK: - Dashboard

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 14) {
            ActivityCalendarCard()
            WritingCard(site: current)
        }
    }

    // MARK: - Recent pages and files

    /// How many of each to show.
    private static let recentCount = 6

    /// Pages by when their file last changed (here, in Finder or from
    /// another Mac), newest first. Link menus and the Template are left out.
    private var recentPages: [(page: ContentItem, edited: Date)] {
        var list: [(page: ContentItem, edited: Date)] = []
        for page in current.items where !page.isLinkMenu && !page.isTemplatePage {
            let values = try? page.fileURL.resourceValues(forKeys: [.contentModificationDateKey])
            if let edited = values?.contentModificationDate { list.append((page, edited)) }
        }
        list.sort { $0.edited > $1.edited }
        return Array(list.prefix(Self.recentCount))
    }

    private var recentFiles: [MediaFile] {
        Array(model.files.filter { $0.added != .distantPast }
            .sorted { $0.added > $1.added }
            .prefix(Self.recentCount))
    }

    /// The two lists side by side, or one above the other when narrow.
    @ViewBuilder
    private var recent: some View {
        let pages = recentPages
        let files = recentFiles
        if !pages.isEmpty || !files.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    recentPagesList(pages).frame(minWidth: 320)
                    recentFilesList(files).frame(minWidth: 320)
                }
                VStack(alignment: .leading, spacing: 24) {
                    recentPagesList(pages)
                    recentFilesList(files)
                }
            }
        }
    }

    private func recentPagesList(_ pages: [(page: ContentItem, edited: Date)]) -> some View {
        RecentList(title: "Recently Edited", seeAll: "All Pages", empty: "No pages yet.",
                   seeAllAction: { model.selection = .pages }) {
            ForEach(pages, id: \.page.id) { entry in
                let page = entry.page
                RecentRow(title: page.title.isEmpty ? page.slug : page.title,
                          detail: "\(kindName(page)) · edited \(entry.edited.formatted(.relative(presentation: .named)))",
                          isDraft: page.isDraft && !page.isHome,
                          help: "Edit “\(page.title)”") {
                    Image(systemName: icon(for: page))
                        .font(.system(size: 16))
                        .foregroundStyle(.tint)
                        .frame(width: 36, height: 36)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                } action: {
                    model.selection = .item(page.id)
                }
            }
        }
    }

    private func recentFilesList(_ files: [MediaFile]) -> some View {
        RecentList(title: "Recently Added Files", seeAll: "All Files", empty: "No files yet. Images you add to pages show here.",
                   seeAllAction: { model.selection = .files }) {
            ForEach(files) { file in
                RecentRow(title: file.name,
                          detail: "added \(file.added.formatted(.relative(presentation: .named))) · "
                              + ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file),
                          help: "Show \(file.name) in Files") {
                    FileThumbnail(file: file, size: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } action: {
                    model.showFile(file.path)
                }
            }
        }
    }

    private func kindName(_ page: ContentItem) -> String {
        if page.isHome { return "Home" }
        if page.isNotFoundPage { return "Broken links page" }
        if page.isSearchPage { return "Search" }
        return current.config.singularName(page.kind)
    }

    private func icon(for page: ContentItem) -> String {
        page.isHome ? "house" : page.isNotFoundPage ? "exclamationmark.triangle"
            : page.isSearchPage ? "magnifyingglass" : current.config.systemImage(page.kind)
    }
}

/// A titled list on the Start page, with a link to see everything.
private struct RecentList<Rows: View>: View {
    let title: String
    let seeAll: String
    let empty: String
    let seeAllAction: () -> Void
    @ViewBuilder let rows: Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button(seeAll, action: seeAllAction)
                    .buttonStyle(.link)
                    .font(.callout)
            }
            VStack(spacing: 6) {
                Group(subviews: rows) { subviews in
                    if subviews.isEmpty {
                        Text(empty)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(subviews) { $0 }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// One page or file: a picture, its name and when, opened with one click.
private struct RecentRow<Icon: View>: View {
    let title: String
    let detail: String
    var isDraft = false
    let help: String
    @ViewBuilder let icon: Icon
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title).lineLimit(1).truncationMode(.middle)
                        if isDraft {
                            Text("Draft")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.14), in: Capsule())
                        }
                    }
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(isHovered ? 0.08 : 0.05), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
    }
}

/// One activity: a colored icon, a title and a short description. Lifts a
/// little when the pointer is over it. Large tiles get a wash of their
/// color and bigger type.
private struct StartTile: View {
    struct Tile: Identifiable {
        var title: String
        var detail: String
        var icon: String
        var color: Color
        var action: () -> Void
        var id: String { title }
    }

    let tile: Tile
    var isLarge = false
    @State private var isHovered = false

    var body: some View {
        Button(action: tile.action) {
            Group {
                if isLarge { largeContent } else { smallContent }
            }
            .padding(isLarge ? 20 : 14)
            .background(background)
            .contentShape(RoundedRectangle(cornerRadius: isLarge ? 18 : 14))
            .scaleEffect(isHovered ? 1.015 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var iconView: some View {
        Image(systemName: tile.icon)
            .font(.system(size: isLarge ? 28 : 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: isLarge ? 58 : 36, height: isLarge ? 58 : 36)
            .background(tile.color.gradient, in: RoundedRectangle(cornerRadius: isLarge ? 14 : 9))
            .shadow(color: isLarge ? tile.color.opacity(0.35) : .clear, radius: 8, y: 3)
    }

    /// Icon on top, big title, and a description, with no extra space below.
    private var largeContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            iconView
            VStack(alignment: .leading, spacing: 4) {
                Text(tile.title).font(.title2.bold())
                Text(tile.detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    // Two lines kept for both, so the pair matches in height.
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// Compact: icon beside the title and a two-line description, so all
    /// small tiles are the same height without extra space underneath.
    private var smallContent: some View {
        HStack(alignment: .top, spacing: 12) {
            iconView
            VStack(alignment: .leading, spacing: 2) {
                Text(tile.title).font(.headline)
                Text(tile.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var background: some View {
        if isLarge {
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(colors: [tile.color.opacity(isHovered ? 0.24 : 0.18),
                                              tile.color.opacity(isHovered ? 0.08 : 0.05)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(tile.color.opacity(0.25)))
        } else {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.primary.opacity(isHovered ? 0.08 : 0.05))
        }
    }
}
