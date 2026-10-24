import AppKit
import SwiftUI

/// Turns the footer on or off and sets what's in it.
struct FooterSection: View {
    @Environment(AppModel.self) private var model
    @Binding var config: SiteConfig

    private var footer: Binding<SiteConfig.Footer> { $config.footer }

    var body: some View {
        Section {
            Toggle(isOn: footer.enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show a footer")
                    Text("A line at the bottom of every page.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
        }

        if config.footer.enabled {
            Section("Copyright") {
                Toggle("Copyright notice", isOn: footer.showCopyright)
                    .toggleStyle(.switch)
                if config.footer.showCopyright {
                    LabeledContent("Name") {
                        VStack(alignment: .trailing, spacing: 2) {
                            TextField("Name", text: footer.copyrightName, prompt: Text(defaultName))
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                            Text("Shows as “\(config.copyrightText())”. The year updates by itself.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                ForEach(config.footer.links.indices, id: \.self) { i in
                    LinkRow(links: footer.links, index: i)
                }
                Menu("Add Link") {
                    Button("Privacy Policy") { add("Privacy Policy", "/privacy-policy/") }
                    Button("Terms and Conditions") { add("Terms and Conditions", "/terms-and-conditions/") }
                    Button("Contact") { add("Contact", "/contact/") }
                    Divider()
                    Button("Other Link") { add("New Link", "https://") }
                }
                .fixedSize()
            } header: {
                Text("Links")
            } footer: {
                Text("Footer links can go to your own pages, such as /privacy-policy/, or to other sites with a full https:// address.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Link to RSS feed", isOn: footer.showFeed)
                    .toggleStyle(.switch)
                FooterMenuRows(menus: footer.menus)
            } header: {
                Text("Buttons")
            } footer: {
                Text("Drop-down menus open a list of links from a Link Menu page, such as your social accounts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Logo") {
                FooterLogoRows(config: $config)
            }

            Section("CardStock Attribution") {
                Toggle(isOn: footer.attribution.enabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Link to CardStock")
                        Text("A link to CardStock on GitHub. It opens in a new window.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                if config.footer.attribution.enabled {
                    TextField("Text", text: footer.attribution.text,
                              prompt: Text(SiteConfig.Footer.Attribution.defaultText))
                }
            }
        }
    }

    private var defaultName: String {
        let author = config.author.trimmingCharacters(in: .whitespaces)
        return author.isEmpty ? config.title : author
    }

    private func add(_ title: String, _ url: String) {
        config.footer.links.append(.init(title: title, url: url))
    }
}

/// Drop-down menu buttons next to the RSS button. Each is filled from a
/// link menu page (a page of links, `type: links`).
private struct FooterMenuRows: View {
    @Environment(AppModel.self) private var model
    @Binding var menus: [SiteConfig.Footer.Menu]

    private var linkMenus: [ContentItem] { model.site?.items(.links) ?? [] }

    var body: some View {
        ForEach(menus.indices, id: \.self) { i in
            if menus.indices.contains(i) { row(i) }
        }

        HStack {
            if linkMenus.isEmpty {
                Button("Add Drop Menu…") { createLinkMenu(addingMenu: true) }
                    .help("Make a link menu page for your links and add a button for it to the footer")
            } else {
                Button("Add Drop Menu") {
                    let page = linkMenus[0]
                    menus.append(.init(title: page.title, page: page.slug))
                }
                .help("A button next to RSS that opens a list of links")
            }
            Spacer()
        }
    }

    private func row(_ i: Int) -> some View {
        let page = linkMenus.first { $0.slug == menus[i].page }
        let count = page.map { LinkMenu.links(in: $0.body).count }
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Button text", text: $menus[i].title, prompt: Text(page?.title ?? "Follow"))
                    .labelsHidden()
                    .frame(maxWidth: 170)
                Picker("Links from", selection: $menus[i].page) {
                    if page == nil {
                        Text("Choose a link menu").tag(menus[i].page)
                    }
                    ForEach(linkMenus) { menu in
                        Text(menu.title).tag(menu.slug)
                    }
                }
                .labelsHidden()
                Button { model.selection = .item(page!.id) } label: { Image(systemName: "pencil") }
                    .disabled(page == nil)
                    .help("Edit the links")
                Button { move(i, by: -1) } label: { Image(systemName: "chevron.up") }
                    .disabled(i == 0)
                    .help("Move left")
                Button { move(i, by: 1) } label: { Image(systemName: "chevron.down") }
                    .disabled(i == menus.count - 1)
                    .help("Move right")
                Button { menus.remove(at: i) } label: { Image(systemName: "minus.circle") }
                    .help("Remove")
            }
            .buttonStyle(.borderless)

            if page == nil {
                note("The link menu page for this button is missing. Choose another, or make one.", button: "New Link Menu…") {
                    createLinkMenu(addingMenu: false, replacing: i)
                }
            } else if count == 0 {
                note("“\(page!.title)” has no links yet, so this button won't show.", button: "Edit Links") {
                    model.selection = .item(page!.id)
                }
            }
        }
    }

    private func note(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(button, action: action)
                .controlSize(.small)
        }
    }

    /// Makes a "Social Links" link menu page, uses it, and opens it to edit.
    private func createLinkMenu(addingMenu: Bool, replacing index: Int? = nil) {
        let title = "Social Links"
        let before = Set(model.site?.items.map(\.id) ?? [])
        guard model.newItem(.links, title: title) != nil,
              let page = model.site?.items.first(where: { !before.contains($0.id) })
        else { return }
        if let index, menus.indices.contains(index) {
            menus[index].page = page.slug
        } else if addingMenu {
            menus.append(.init(title: "Follow", page: page.slug))
        }
    }

    private func move(_ i: Int, by offset: Int) {
        let j = i + offset
        guard menus.indices.contains(j) else { return }
        menus.swapAt(i, j)
    }
}

/// The footer logo: an image from Files, its size in pixels, where it sits,
/// and the space around it when it's on its own row.
private struct FooterLogoRows: View {
    @Binding var config: SiteConfig

    private var logo: Binding<SiteConfig.Footer.Logo> { $config.footer.logo }

    var body: some View {
        LogoImageRows(image: logo.image, width: logo.width, height: logo.height,
                      sheetTitle: "Choose a Footer Logo")

        if config.footer.logo.hasImage {
            TextField("Description", text: logo.alt, prompt: Text(config.title))
                .help("Read aloud by screen readers. Leave empty to use the site title.")

            Picker("Position", selection: logo.placement) {
                Text("Left of the copyright").tag(SiteConfig.Footer.Logo.Placement.left)
                Text("Centered below").tag(SiteConfig.Footer.Logo.Placement.below)
            }

            if config.footer.logo.placement == .below {
                LabeledContent("Space above") {
                    HStack(spacing: 6) {
                        PixelField(label: "Space above", value: logo.paddingTop)
                        Text("px").foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Space below") {
                    HStack(spacing: 6) {
                        PixelField(label: "Space below", value: logo.paddingBottom)
                        Text("px").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// One link (footer or top bar): its text and address, reorder and remove
/// buttons, and a way to make the page when the address points to a page
/// that doesn't exist yet.
struct LinkRow: View {
    @Environment(AppModel.self) private var model
    @Binding var links: [SiteConfig.NavLink]
    let index: Int
    /// Example address shown in an empty field.
    var addressPrompt = "/privacy-policy/"
    /// Top bar links also get an icon and a Button switch.
    var topBarOptions = false

    var body: some View {
        if links.indices.contains(index) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    TextField("Text", text: $links[index].title)
                        .labelsHidden()
                        .frame(maxWidth: 170)
                    TextField("Address", text: $links[index].url, prompt: Text(addressPrompt))
                        .labelsHidden()
                    pageMenu
                    Button { move(by: -1) } label: { Image(systemName: "chevron.up") }
                        .disabled(index == 0)
                        .help("Move up")
                    Button { move(by: 1) } label: { Image(systemName: "chevron.down") }
                        .disabled(index == links.count - 1)
                        .help("Move down")
                    Button { links.remove(at: index) } label: { Image(systemName: "minus.circle") }
                        .help("Remove")
                }
                .buttonStyle(.borderless)

                if topBarOptions {
                    HStack(spacing: 12) {
                        NavIconMenu(icon: $links[index].icon)
                        Toggle("Button", isOn: $links[index].button)
                            .toggleStyle(.checkbox)
                            .help("Show this link as a button, styled in Button Style below")
                        if links[index].title.trimmingCharacters(in: .whitespaces).isEmpty && !links[index].icon.isEmpty {
                            Text("Icon only")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                    .controlSize(.small)
                }

                if isMissingPage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                        Text("There's no page at \(links[index].url) yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Create Page") { createPage() }
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    /// Picks one of the site's pages as the address. A link still called
    /// "New Link" (or with no text) takes the page's title too.
    private var pageMenu: some View {
        Menu {
            Button("Home") { choose("/", title: model.site?.home?.title ?? "Home") }
            let config = model.site?.config ?? SiteConfig()
            if !config.collections.isEmpty {
                Section("Collections") {
                    ForEach(config.collections) { c in
                        Button(c.name) { choose(c.mainPath, title: model.site?.mainPage(of: c)?.title ?? c.name) }
                    }
                }
            }
            if config.tags.pages {
                Button("Tags") { choose(TagSettings.path, title: "Tags") }
            }
            ForEach(config.kinds.filter { $0 != .links }, id: \.self) { kind in
                let pages = (model.site?.items(kind) ?? []).filter { !$0.isHome && !$0.isTemplatePage }
                if !pages.isEmpty {
                    Section(config.pluralName(kind)) {
                        ForEach(pages) { page in
                            Button(page.isDraft ? "\(page.title) (draft)" : page.title) {
                                choose(page.path, title: page.title)
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "doc.text")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .help("Choose a page")
    }

    private func choose(_ path: String, title: String) {
        guard links.indices.contains(index) else { return }
        links[index].url = path
        let current = links[index].title.trimmingCharacters(in: .whitespaces)
        if current.isEmpty || current == "New Link" { links[index].title = title }
    }

    /// True for an address on this site that no page, post or list has.
    private var isMissingPage: Bool {
        let url = links[index].url.trimmingCharacters(in: .whitespaces)
        guard url.hasPrefix("/"), !url.hasPrefix("//"), url != "/",
              !url.hasPrefix("/posts/"), !url.hasPrefix("/portfolio/"), !url.hasPrefix("/media/"),
              !url.hasPrefix("/assets/"), !url.contains(".")
        else { return false }
        let normalized = url.hasSuffix("/") ? url : url + "/"
        return !(model.site?.items.contains { $0.path == normalized } ?? false)
    }

    /// Makes a page named after the link, points the link at it, and opens it.
    private func createPage() {
        let title = links[index].title.trimmingCharacters(in: .whitespaces)
        let i = index
        guard let path = model.newItem(.page, title: title.isEmpty ? "New Page" : title) else { return }
        if links.indices.contains(i) { links[i].url = path }
    }

    private func move(by offset: Int) {
        let j = index + offset
        guard links.indices.contains(j) else { return }
        links.swapAt(index, j)
    }
}

/// Picks a top bar link's icon from the bundled set (`NavIcon`), shown here
/// as look-alike SF Symbols.
struct NavIconMenu: View {
    @Binding var icon: String

    var body: some View {
        Menu {
            Button("No Icon") { icon = "" }
            ForEach(NavIcon.groups, id: \.self) { group in
                Section(group) {
                    ForEach(NavIcon.all.filter { $0.group == group }) { item in
                        Button { icon = item.id } label: {
                            Label(item.name, systemImage: item.symbol)
                        }
                    }
                }
            }
        } label: {
            if let current = NavIcon.named(icon) {
                Label(current.name, systemImage: current.symbol)
            } else {
                Label("Icon", systemImage: "plus.circle")
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("An icon shown with the link's text. Leave the text empty to show just the icon.")
    }
}
