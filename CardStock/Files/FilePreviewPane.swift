import AppKit
import ImageIO
import Quartz
import SwiftUI

/// The right column on the Files page: a preview of the selected file with
/// its details and quick actions.
struct FilePreviewPane: View {
    @Environment(AppModel.self) private var model
    @State private var pendingDelete: [MediaFile] = []

    private var selected: [MediaFile] {
        model.files.filter { model.selectedFileIDs.contains($0.id) }
    }

    var body: some View {
        Group {
            switch selected.count {
            case 0:
                ContentUnavailableView("No File Selected", systemImage: "photo",
                                       description: Text("Select a file to preview it here."))
            case 1:
                SingleFilePreview(file: selected[0], onDelete: { pendingDelete = [selected[0]] })
                    .id(selected[0].id)
            default:
                ContentUnavailableView {
                    Label("\(selected.count) Files Selected", systemImage: "square.stack")
                } description: {
                    Text(ByteCountFormatter.string(fromByteCount: selected.reduce(0) { $0 + $1.size }, countStyle: .file))
                } actions: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tags on all \(selected.count) files")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        FileTagEditor(files: selected)
                    }
                    .frame(maxWidth: 320)
                    .padding(.bottom, 6)
                    Button("Copy Markdown for All") { model.copyMarkdown(for: selected) }
                    Button("Move \(selected.count) Files to Trash…", role: .destructive) { pendingDelete = selected }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
        .confirmationDialog(pendingDelete.count == 1 ? "Move “\(pendingDelete.first?.name ?? "")” to the Trash?"
                                                     : "Move \(pendingDelete.count) files to the Trash?",
                            isPresented: Binding(get: { !pendingDelete.isEmpty },
                                                 set: { if !$0 { pendingDelete = [] } })) {
            Button("Move to Trash", role: .destructive) {
                pendingDelete.forEach(model.deleteFile)
                model.selectedFileIDs.subtract(pendingDelete.map(\.id))
                pendingDelete = []
            }
        } message: {
            Text(FilesView.deleteMessage(for: pendingDelete))
        }
    }
}

private struct SingleFilePreview: View {
    @Environment(AppModel.self) private var model
    let file: MediaFile
    let onDelete: () -> Void
    @State private var image: NSImage?
    @State private var pixelSize: CGSize?
    @State private var smallPixelSize: CGSize?

    private var url: URL? { model.site?.root.appending(path: file.path) }

    var body: some View {
        VStack(spacing: 0) {
            if file.isImage && ImageEditor.canEdit(file.path) {
                ImageToolbar(file: file)
                Divider()
            }
            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)
                .overlay {
                    if model.isEditingImage {
                        ProgressView().controlSize(.large)
                            .padding(18)
                            .glassEffect(.regular, in: .rect(cornerRadius: 14))
                    }
                }
            Divider()
            details
                .padding(18)
                .background(.bar)
        }
        .task(id: "\(file.id)#\(model.mediaRevision)") { await load() }
    }

    @ViewBuilder
    private var preview: some View {
        if file.isImage {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
            } else {
                ProgressView()
            }
        } else if let url {
            QuickLookPreview(url: url)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(file.name)
                .font(.headline)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 4) {
                if let pixelSize {
                    row("Size", "\(Int(pixelSize.width)) × \(Int(pixelSize.height)) px · \(bytes(file.size))")
                } else {
                    row("Size", bytes(file.size))
                }
                if let small = file.smallPath, let smallPixelSize {
                    row("On page", "\(Int(smallPixelSize.width)) × \(Int(smallPixelSize.height)) px (\((small as NSString).lastPathComponent))")
                }
                if file.added != .distantPast {
                    row("Added", file.added.formatted(date: .long, time: .shortened))
                }
                row("Location", file.folder)
                GridRow {
                    Text("Tags").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    FileTagEditor(files: [file])
                }
                GridRow {
                    Text("Used on").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    if file.usedIn.isEmpty {
                        Text("Not used on any page").foregroundStyle(.orange)
                    } else {
                        usedOnLinks
                    }
                }
            }
            .font(.callout)

            HStack(spacing: 8) {
                Button("Copy Markdown", systemImage: "doc.on.clipboard") { model.copyMarkdown(for: [file]) }
                Button("Open", systemImage: "arrow.up.forward.app") { if let url { NSWorkspace.shared.open(url) } }
                Button("Show in Finder", systemImage: "folder") {
                    if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                Button("Duplicate", systemImage: "plus.square.on.square") { model.duplicateFile(file) }
                    .help(file.smallPath != nil ? "Make a copy of both sizes of this image" : "Make a copy of this file")
                Spacer(minLength: 0)
                Button("Move to Trash…", systemImage: "trash", role: .destructive, action: onDelete)
                    .foregroundStyle(.red)
                    .help("Move to your Mac's Trash. The next publish removes it from GitHub too.")
            }
            .controlSize(.small)
            .labelStyle(.titleAndIcon)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Each page that uses the file, as a link that opens it.
    private var usedOnLinks: some View {
        HStack(spacing: 6) {
            ForEach(file.usedIn, id: \.self) { title in
                if let item = model.site?.items.first(where: { $0.title == title }) {
                    Button(title) { model.selection = .item(item.id) }
                        .buttonStyle(.link)
                } else {
                    Text(title)
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).textSelection(.enabled)
        }
    }

    private func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }

    /// Loads a screen-sized version of the image and the pixel sizes, off
    /// the main thread.
    private func load() async {
        guard file.isImage, let root = model.site?.root else { return }
        let largeURL = root.appending(path: file.path)
        let smallURL = file.smallPath.map { root.appending(path: $0) }
        let result = await Task.detached(priority: .userInitiated) { () -> (CGImage?, CGSize?, CGSize?) in
            func size(_ url: URL) -> CGSize? {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let w = props[kCGImagePropertyPixelWidth] as? Int,
                      let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
                let rotated = (props[kCGImagePropertyOrientation] as? Int ?? 1) >= 5
                return rotated ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
            }
            var image: CGImage?
            if let source = CGImageSourceCreateWithURL(largeURL as CFURL, nil) {
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1600,
                ]
                image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            }
            return (image, size(largeURL), smallURL.flatMap(size))
        }.value
        if let cg = result.0 { image = NSImage(cgImage: cg, size: .zero) }
        pixelSize = result.1
        smallPixelSize = result.2
    }
}

/// Tools along the top of an image preview: rotate, flip, crop, Auto
/// Enhance, Apple's photo filters, Remove Background, and Undo.
private struct ImageToolbar: View {
    @Environment(AppModel.self) private var model
    let file: MediaFile

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 8) {
                tool("rotate.left", "Rotate Left") { model.editImage(file, .rotateLeft) }
                tool("rotate.right", "Rotate Right") { model.editImage(file, .rotateRight) }
                tool("arrow.left.and.right.righttriangle.left.righttriangle.right", "Flip Horizontal") {
                    model.editImage(file, .flipHorizontal)
                }
                tool("arrow.up.and.down.righttriangle.up.righttriangle.down", "Flip Vertical") {
                    model.editImage(file, .flipVertical)
                }

                menu("crop", "Crop") {
                    ForEach(ImageEditor.AspectRatio.allCases, id: \.self) { aspect in
                        Button("Crop to \(aspect.rawValue)") { model.editImage(file, .crop(aspect)) }
                    }
                }

                tool("wand.and.stars", "Auto Enhance") { model.editImage(file, .autoEnhance) }

                menu("camera.filters", "Filters") {
                    ForEach(ImageEditor.PhotoFilter.allCases, id: \.self) { filter in
                        Button(filter.name) { model.editImage(file, .filter(filter)) }
                    }
                }

                tool("person.and.background.dotted", "Remove Background (saves a new PNG)") {
                    model.removeBackground(file)
                }

                Spacer(minLength: 0)

                tool("arrow.uturn.backward", "Undo Last Change") { model.undoImageEdit(file) }
                    .disabled(!model.canUndoImageEdit(file))
                    .opacity(model.canUndoImageEdit(file) ? 1 : 0.4)
            }
            .disabled(model.isEditingImage)
            .padding(.horizontal, 10)
            .frame(height: PreviewBar.barHeight)
        }
    }

    private func tool(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .roundGlass(32)
        .help(help)
        .accessibilityLabel(help)
    }

    private func menu<Content: View>(_ symbol: String, _ help: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .roundGlass(32)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// macOS's Quick Look preview, for PDFs, videos and other files.
private struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL) as URL? != url {
            view.previewItem = url as NSURL
        }
    }
}

/// Tags on one or more files. With several, it shows the tags they all
/// have; adding or removing one changes every file.
struct FileTagEditor: View {
    @Environment(AppModel.self) private var model
    let files: [MediaFile]

    /// The files as they are now (the list refreshes after each change).
    private var current: [MediaFile] {
        files.map { file in model.files.first { $0.id == file.id } ?? file }
    }

    private var common: [String] {
        guard let first = current.first else { return [] }
        return first.tags.filter { tag in current.allSatisfy { $0.tags.contains { TagSettings.slug($0) == TagSettings.slug(tag) } } }
    }

    var body: some View {
        TagEditor(tags: Binding(
            get: { common },
            set: { new in
                let old = common
                let added = new.filter { tag in !old.contains { TagSettings.slug($0) == TagSettings.slug(tag) } }
                let removed = old.filter { tag in !new.contains { TagSettings.slug($0) == TagSettings.slug(tag) } }
                model.changeTags(of: current, adding: added, removing: removed)
            }), suggestions: model.site?.tagIndex().map(\.name) ?? [])
            .controlSize(.small)
    }
}
