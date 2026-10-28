import AppKit
import SwiftUI

/// Configuration → Templates: a gallery of CardStock's templates and the
/// ones saved on this Mac, each a small preview drawn from its settings.
/// Saved ones have a menu to use, update, rename, export and delete them.
struct StylesSection: View {
    @Environment(AppModel.self) private var model

    private enum NameAction: Identifiable {
        case saveCurrent
        case saveUnsaved
        case rename(SavedStyle)
        var id: String {
            switch self {
            case .saveCurrent: "save-current"
            case .saveUnsaved: "save-unsaved"
            case .rename(let style): "rename-\(style.id)"
            }
        }
    }

    @State private var nameAction: NameAction?
    @State private var nameText = ""
    @State private var pendingDelete: SavedStyle?
    @State private var pendingUpdate: SavedStyle?

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 14, alignment: .top)]

    var body: some View {
        Section {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                TemplateCard(name: "CardStock Default", summary: "The starter look: serif text with sans serif headings.",
                             theme: ThemeSettings(), isSelected: model.currentStyleChoice == .builtInDefault) {
                    model.applyDefaultStyle()
                }
                ForEach(BuiltInTemplate.all) { template in
                    TemplateCard(name: template.name, summary: template.summary, theme: template.theme,
                                 isSelected: model.currentStyleChoice == .builtIn(template.id)) {
                        model.applyBuiltInTemplate(template)
                    }
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text("Templates")
        } footer: {
            Text("Click a template to use it on this site. It sets the fonts, colors, width and the look of buttons, cards and corners, which you can change on the pages below. Your own look is kept as Unsaved Template until you quit, so you can switch back.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section {
            if model.styles.isEmpty && model.unsavedStyleTheme == nil {
                Text("Save this site's look to use it on your other sites.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    if let unsaved = model.unsavedStyleTheme {
                        TemplateCard(name: "Unsaved Template", summary: "Not saved yet. Kept until you quit CardStock.",
                                     theme: unsaved, isSelected: model.currentStyleChoice == .unsaved,
                                     note: .orange) {
                            model.applyUnsavedStyle()
                        }
                        .contextMenu {
                            Button("Save as New Template…") {
                                askForName(model.currentStyleChoice == .unsaved ? .saveCurrent : .saveUnsaved)
                            }
                        }
                    }
                    ForEach(model.styles) { style in
                        TemplateCard(name: style.name, summary: "Saved \(style.savedAt.formatted(date: .abbreviated, time: .omitted))",
                                     theme: style.theme, isSelected: model.currentStyleChoice == .saved(style.id),
                                     menu: AnyView(menuItems(for: style))) {
                            model.applyStyle(style)
                        }
                        .contextMenu { menuItems(for: style) }
                    }
                }
                .padding(.vertical, 6)
            }
            HStack {
                Button("Save Current Look…") { askForName(.saveCurrent) }
                    .disabled(model.currentStyleChoice != .unsaved)
                    .help(model.currentStyleChoice == .unsaved
                          ? "Save this site's look as a template for your other sites"
                          : "This site's look is already a template")
                Spacer()
                Button("Import…", action: importStyles)
            }
        } header: {
            Text("My Templates")
        } footer: {
            Text("Templates you save are kept on this Mac and shared by all your sites. Right-click one to update, rename, export or delete it. Using a template copies it into this site, so the site keeps its look even on a Mac without it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .alert(nameAlertTitle, isPresented: Binding(get: { nameAction != nil }, set: { if !$0 { nameAction = nil } })) {
            TextField("Name", text: $nameText)
            Button("Cancel", role: .cancel) { nameAction = nil }
            Button(nameAlertButton) { finishNaming() }
        }
        .confirmationDialog("Update this template?", isPresented: Binding(
            get: { pendingUpdate != nil }, set: { if !$0 { pendingUpdate = nil } }), presenting: pendingUpdate) { style in
            Button("Update “\(style.name)”") { model.updateStyle(style) }
        } message: { style in
            Text("“\(style.name)” will be replaced with this site's current look. Sites already using it keep their own copy.")
        }
        .confirmationDialog("Delete this template?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), presenting: pendingDelete) { style in
            Button("Delete “\(style.name)”", role: .destructive) { model.deleteStyle(style) }
        } message: { _ in
            Text("Sites that use it keep their look. This can't be undone, so export it first if you might want it later.")
        }
    }

    // MARK: - Menus

    @ViewBuilder
    private func menuItems(for style: SavedStyle) -> some View {
        Button("Use for This Site") { model.applyStyle(style) }
            .disabled(model.activeStyle?.id == style.id)
        Button("Update with This Site's Look…") { pendingUpdate = style }
            .disabled(model.activeStyle?.id == style.id)
        Button("Rename…") { askForName(.rename(style)) }
        Button("Export…") { export(style) }
        Divider()
        Button("Delete…", role: .destructive) { pendingDelete = style }
    }

    // MARK: - Naming

    private func askForName(_ action: NameAction) {
        switch action {
        case .saveCurrent, .saveUnsaved:
            nameText = model.site?.config.title ?? "My Template"
        case .rename(let style):
            nameText = style.name
        }
        nameAction = action
    }

    private var nameAlertTitle: String {
        if case .rename = nameAction { return "Rename Template" }
        return "Save Template"
    }

    private var nameAlertButton: String {
        if case .rename = nameAction { return "Rename" }
        return "Save"
    }

    private func finishNaming() {
        switch nameAction {
        case .saveCurrent: model.saveCurrentStyle(as: nameText)
        case .saveUnsaved: model.saveUnsavedStyle(as: nameText)
        case .rename(let style): model.renameStyle(style, to: nameText)
        case nil: break
        }
        nameAction = nil
    }

    // MARK: - Files

    private func export(_ style: SavedStyle) {
        let panel = NSSavePanel()
        panel.title = "Export Template"
        panel.nameFieldStringValue = "\(style.name).\(StyleLibrary.fileExtension)"
        panel.allowedContentTypes = [StyleLibrary.fileType]
        panel.message = "Share this file. Anyone with CardStock can import it."
        if panel.runModal() == .OK, let url = panel.url {
            model.exportStyle(style, to: url)
        }
    }

    private func importStyles() {
        let panel = NSOpenPanel()
        panel.title = "Import Templates"
        panel.allowedContentTypes = [StyleLibrary.fileType, StyleLibrary.legacyFileType, .json]
        panel.allowsMultipleSelection = true
        panel.message = "Choose .cardstockstyle files (a site's theme.json works too)."
        if panel.runModal() == .OK {
            model.importStyles(from: panel.urls)
        }
    }
}

/// A template in the gallery: a small page drawn in its colors, fonts,
/// corners, buttons and cards, with its name and fonts below. Auto
/// (light and dark) templates show the dark version down the right side.
private struct TemplateCard: View {
    let name: String
    let summary: String
    let theme: ThemeSettings
    let isSelected: Bool
    var note: Color?
    var menu: AnyView?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: action) {
                TemplatePreview(theme: theme)
                    .aspectRatio(16 / 11, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(hovering ? 0.3 : 0.12),
                                          lineWidth: isSelected ? 3 : 1)
                    }
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.accentColor)
                                .padding(6)
                        }
                    }
                    .shadow(color: .black.opacity(hovering ? 0.12 : 0.05), radius: hovering ? 6 : 2, y: 1)
                    .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
            .help(isSelected ? "This site uses \(name)" : "Use \(name) on this site")

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(note ?? .secondary)
                        .lineLimit(2, reservesSpace: true)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(TemplatePreview.fontNames(theme))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let menu {
                    Menu { menu } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("Template options")
                }
            }
        }
    }
}

/// A tiny page in a template's style: top bar, heading, text, a button and
/// a card.
struct TemplatePreview: View {
    let theme: ThemeSettings

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / 240
            ZStack(alignment: .topLeading) {
                page(theme.appearance == .dark ? theme.dark : theme.light, scale: scale)
                if theme.appearance == .auto {
                    page(theme.dark, scale: scale)
                        .mask(alignment: .trailing) {
                            Rectangle().frame(width: geo.size.width * 0.3)
                        }
                    Rectangle()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 1)
                        .offset(x: geo.size.width * 0.7)
                }
            }
        }
    }

    private func page(_ p: ThemeSettings.Palette, scale s: CGFloat) -> some View {
        let text = color(p.text), muted = color(p.muted), accent = color(p.accent)
        let surface = color(p.surface), line = color(p.line)
        return VStack(alignment: .leading, spacing: 0) {
            // Top bar
            HStack(spacing: 5 * s) {
                RoundedRectangle(cornerRadius: min(theme.radius, 6) * s)
                    .fill(accent)
                    .frame(width: 12 * s, height: 12 * s)
                bar(muted, width: 34 * s, s)
                Spacer()
                bar(muted, width: 18 * s, s)
                bar(muted, width: 18 * s, s)
                bar(muted, width: 18 * s, s)
            }
            .padding(.horizontal, 14 * s)
            .frame(height: 26 * s)
            .overlay(alignment: .bottom) { line.frame(height: max(0.5, 0.75 * s)) }

            VStack(alignment: .leading, spacing: 7 * s) {
                Text("Hello there")
                    .font(.system(size: min(theme.h1Size, 48) * 0.5 * s, weight: .bold, design: Self.design(theme.headingFont, theme)))
                    .foregroundStyle(text)
                    .lineLimit(1)
                Text("Stories, projects and notes")
                    .font(.system(size: 9 * s, design: Self.design(theme.bodyFont, theme)))
                    .foregroundStyle(muted)
                    .lineLimit(1)
                HStack(alignment: .top, spacing: 10 * s) {
                    VStack(alignment: .leading, spacing: 4 * s) {
                        bar(text.opacity(0.55), width: 82 * s, s)
                        bar(text.opacity(0.55), width: 74 * s, s)
                        bar(text.opacity(0.55), width: 80 * s, s)
                        button(accent, background: color(p.background), s)
                            .padding(.top, 4 * s)
                    }
                    card(surface: surface, line: line, accent: accent, muted: muted, s)
                }
                .padding(.top, 2 * s)
            }
            .padding(.horizontal, 14 * s)
            .padding(.top, 12 * s)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color(p.background))
    }

    private func bar(_ c: Color, width: CGFloat, _ s: CGFloat) -> some View {
        Capsule().fill(c).frame(width: width, height: 3.5 * s)
    }

    private func button(_ accent: Color, background: Color, _ s: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: min(theme.buttonRadius * 0.6, 9) * s)
        let filled = theme.buttonStyle == .filled
        return Text("Read more")
            .font(.system(size: 7 * s, weight: .semibold, design: Self.design(theme.headingFont, theme)))
            .foregroundStyle(filled ? background : accent)
            .padding(.horizontal, 7 * s)
            .padding(.vertical, 3.5 * s)
            .background(filled ? accent : .clear, in: shape)
            .overlay { if !filled { shape.strokeBorder(accent, lineWidth: max(0.75, s)) } }
    }

    private func card(surface: Color, line: Color, accent: Color, muted: Color, _ s: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: min(theme.cardRadius * 0.5, 12) * s)
        let shadow: (Double, CGFloat) = switch theme.cardShadow {
        case .none: (0, 0)
        case .soft: (0.10, 4)
        case .strong: (0.25, 8)
        }
        return VStack(alignment: .leading, spacing: 4 * s) {
            RoundedRectangle(cornerRadius: min(theme.coverRadius * 0.4, 8) * s)
                .fill(accent.opacity(0.35))
                .frame(height: 30 * s)
            bar(muted, width: 44 * s, s)
            bar(muted.opacity(0.6), width: 32 * s, s)
        }
        .padding(6 * s)
        .frame(width: 84 * s, alignment: .leading)
        .background(surface, in: shape)
        .overlay { if theme.cardBorder { shape.strokeBorder(line, lineWidth: max(0.75, s)) } }
        .shadow(color: .black.opacity(shadow.0), radius: shadow.1 * s, y: shadow.1 * s / 3)
    }

    private func color(_ hex: String) -> Color { Color(hex: hex) ?? .gray }

    /// The closest Mac font style to a theme font, since web fonts aren't
    /// installed on the Mac.
    static func design(_ id: String, _ theme: ThemeSettings) -> Font.Design {
        if let font = ThemeFont.named(id) {
            switch font.category {
            case .serif, .display: return .serif
            case .mono: return .monospaced
            case .sans: return .default
            case .system:
                if id.contains("serif") { return .serif }
                if id.contains("rounded") { return .rounded }
                if id.contains("mono") { return .monospaced }
                return .default
            }
        }
        switch theme.customFonts.first(where: { $0.id == id })?.style {
        case .serif: return .serif
        case .mono: return .monospaced
        default: return .default
        }
    }

    /// "Playfair Display / Lora": headings, then body text.
    static func fontNames(_ theme: ThemeSettings) -> String {
        func name(_ id: String) -> String {
            ThemeFont.named(id)?.name ?? theme.customFonts.first { $0.id == id }?.family ?? "Default"
        }
        return theme.bodyFont == theme.headingFont
            ? name(theme.bodyFont)
            : "\(name(theme.headingFont)) / \(name(theme.bodyFont))"
    }
}
