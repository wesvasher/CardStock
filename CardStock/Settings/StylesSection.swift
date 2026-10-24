import AppKit
import SwiftUI

/// Saved styles: a menu to switch this site's style, plus save, import,
/// and a Manage menu to update, rename, export and delete styles.
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

    var body: some View {
        Section {
            HStack(spacing: 10) {
                Swatches(theme: model.currentTheme)
                Picker("Template", selection: choice) {
                    if model.unsavedStyleTheme != nil {
                        Text("Unsaved Template").tag(AppModel.StyleChoice.unsaved)
                    }
                    if !model.styles.isEmpty {
                        Section("Saved Templates") {
                            ForEach(model.styles) { style in
                                Text(style.name).tag(AppModel.StyleChoice.saved(style.id))
                            }
                        }
                    }
                    Divider()
                    Text("CardStock Default").tag(AppModel.StyleChoice.builtInDefault)
                }
            }
            HStack {
                Text(selectedDetail)
                    .font(.caption)
                    .foregroundStyle(model.currentStyleChoice == .unsaved ? Color.orange : Color.secondary)
                Spacer()
                if model.currentStyleChoice == .unsaved {
                    Button("Save as New Template…") { askForName(.saveCurrent) }
                }
            }

            HStack {
                Button("Import…", action: importStyles)
                Spacer()
                Menu("Manage") {
                    ForEach(model.styles) { style in
                        Menu(style.name) { menuItems(for: style) }
                    }
                }
                .fixedSize()
                .disabled(model.styles.isEmpty)
            }
        } header: {
            Text("Templates")
        } footer: {
            Text("Pick a template to use it on this site. Templates are saved on this Mac and shared by all your sites. Using one copies it into this site, so the site keeps its look even on a Mac without the template.")
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

    private var choice: Binding<AppModel.StyleChoice> {
        Binding(
            get: { model.currentStyleChoice },
            set: { newValue in
                switch newValue {
                case .unsaved: model.applyUnsavedStyle()
                case .builtInDefault: model.applyDefaultStyle()
                case .saved(let id):
                    if let style = model.styles.first(where: { $0.id == id }) { model.applyStyle(style) }
                }
            })
    }

    private var selectedDetail: String {
        switch model.currentStyleChoice {
        case .unsaved:
            return "Not saved yet. Kept until you quit CardStock."
        case .builtInDefault:
            return "The starter look"
        case .saved:
            let theme = model.currentTheme
            return theme == ThemeSettings() ? "Same settings as CardStock Default" : fontSummary(theme)
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

    private func fontSummary(_ theme: ThemeSettings) -> String {
        func name(_ id: String) -> String {
            ThemeFont.named(id)?.name ?? theme.customFonts.first { $0.id == id }?.family ?? "Default"
        }
        let fonts = theme.bodyFont == theme.headingFont
            ? name(theme.bodyFont)
            : "\(name(theme.headingFont)) / \(name(theme.bodyFont))"
        return "\(fonts) · \(Int(theme.fontSize)) px"
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

/// A few dots previewing a theme's colors.
private struct Swatches: View {
    let theme: ThemeSettings

    var body: some View {
        let palette = theme.appearance == .dark ? theme.dark : theme.light
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: palette.background) ?? .white)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            HStack(spacing: 3) {
                dot(palette.text)
                dot(palette.accent)
                dot(palette.muted)
            }
        }
        .frame(width: 44, height: 28)
    }

    private func dot(_ hex: String) -> some View {
        Circle()
            .fill(Color(hex: hex) ?? .gray)
            .frame(width: 9, height: 9)
    }
}
