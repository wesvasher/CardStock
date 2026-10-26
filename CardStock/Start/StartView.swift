import AppKit
import SwiftUI

/// What you see when a site opens: tiles for the common things to do, and
/// recent posts to pick up where you left off. The preview is hidden here.
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
                HowItWorksCard()
                // Everything else, all the same size.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
                    ForEach(tiles) { tile in
                        StartTile(tile: tile)
                    }
                }
                dashboard
                recentPosts
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
            // Side by side at the same height when there's room; stacked otherwise.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    HealthCard(site: current).frame(minWidth: 340)
                    WritingCard(site: current).frame(minWidth: 340)
                }
                .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 14) {
                    HealthCard(site: current)
                    WritingCard(site: current)
                }
            }
        }
    }

    // MARK: - Recent posts

    @ViewBuilder
    private var recentPosts: some View {
        let posts = Array(current.items(.post).prefix(4))
        if !posts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent Posts")
                    .font(.headline)
                VStack(spacing: 6) {
                    ForEach(posts) { post in
                        Button { model.selection = .item(post.id) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "doc.text")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                Text(post.title)
                                    .lineLimit(1)
                                if post.isDraft {
                                    Text("Draft")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.orange)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.14), in: Capsule())
                                }
                                Spacer()
                                Text(post.date)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
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
