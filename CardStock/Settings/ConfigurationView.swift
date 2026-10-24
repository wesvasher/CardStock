import AppKit
import SwiftUI

/// One page of the Configuration view.
enum ConfigPage: String, CaseIterable, Identifiable {
    case site, collections, folders, tags, templates, layouts, fonts, colors, topBar, footer, components, newsletter, search

    var id: Self { self }

    /// The name used in Help Center links: `cardstock:<linkName>`.
    var linkName: String {
        switch self {
        case .site: "site-details"
        case .topBar: "top-bar"
        default: rawValue
        }
    }

    var title: String {
        switch self {
        case .site: "Site Details"
        case .collections: "Collections"
        case .folders: "Folders"
        case .tags: "Tags"
        case .templates: "Template"
        case .layouts: "Layout"
        case .fonts: "Fonts"
        case .colors: "Colors"
        case .topBar: "Top Navigation Bar"
        case .footer: "Footer"
        case .components: "Components"
        case .newsletter: "Mailing List"
        case .search: "Search"
        }
    }

    var summary: String {
        switch self {
        case .site: "Title, address and storage"
        case .collections: "Blog, shop, portfolio and more"
        case .folders: "Your site's folders and short addresses"
        case .tags: "Every tag and its page"
        case .templates: "Saved looks to switch between"
        case .layouts: "Page width and page layouts"
        case .fonts: "Typefaces and text sizes"
        case .colors: "Light and dark colors"
        case .topBar: "Menu, logo and bar style"
        case .footer: "Copyright, links, menus and logo"
        case .components: "Buttons, cards, images and more"
        case .newsletter: "A sign-up box for your pages"
        case .search: "A search page and search boxes"
        }
    }

    var systemImage: String {
        switch self {
        case .site: "globe"
        case .collections: "square.stack.3d.up"
        case .folders: "folder"
        case .tags: "tag"
        case .templates: "swatchpalette"
        case .layouts: "rectangle.3.group"
        case .fonts: "textformat"
        case .colors: "paintpalette"
        case .topBar: "menubar.rectangle"
        case .footer: "dock.rectangle"
        case .components: "square.on.square"
        case .newsletter: "envelope"
        case .search: "magnifyingglass"
        }
    }
}

/// Configuration: a fixed-width list of pages, then the selected page's
/// settings, and a preview of the theme page that slides in from the right.
struct ConfigurationView<Preview: View>: View {
    @Environment(AppModel.self) private var model
    let site: Site
    let showPreview: Bool
    @ViewBuilder var preview: Preview
    /// The settings' share of the width when the preview shows.
    @AppStorage("configSplit") private var split = 0.5
    @State private var dragStart: Double?

    var body: some View {
        HStack(spacing: 0) {
            pageList
                .frame(width: 260)
                .frame(maxHeight: .infinity)
            Divider()
            GeometryReader { geo in
                let total = max(geo.size.width, 1)
                let lower = min(360 / total, 0.5)
                let share = min(max(split, lower), 1 - lower)
                HStack(spacing: 0) {
                    settings
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if showPreview {
                        HStack(spacing: 0) {
                            divider(total: total, share: share, lower: lower)
                            preview
                        }
                        .frame(width: total * (1 - share))
                        .frame(maxHeight: .infinity)
                        .transition(.move(edge: .trailing))
                    }
                }
            }
            .clipped()
        }
    }

    private var pageList: some View {
        List(selection: Binding(
            get: { model.configPage },
            set: { if let page = $0 { model.configPage = page } })) {
            ForEach(ConfigPage.allCases) { page in
                HStack(spacing: 10) {
                    Image(systemName: page.systemImage)
                        .foregroundStyle(.tint)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(page.title)
                        Text(page.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 3)
                .tag(page)
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private var settings: some View {
        if model.configPage == .site {
            SiteDetailsView(site: site)
        } else if model.configPage == .layouts {
            LayoutsView()
        } else if model.configPage == .collections {
            CollectionsView()
        } else if model.configPage == .folders {
            FoldersView()
        } else if model.configPage == .tags {
            TagsView()
        } else {
            ThemingView(page: model.configPage)
        }
    }

    /// The line between settings and preview; drag to resize, double-click
    /// to split evenly.
    private func divider(total: CGFloat, share: Double, lower: Double) -> some View {
        Divider()
            .overlay {
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
                                split = min(max(start + value.translation.width / total, lower), 1 - lower)
                            }
                            .onEnded { _ in dragStart = nil })
                    .onTapGesture(count: 2) { split = 0.5 }
            }
            .zIndex(1)
    }
}
