import AppKit
import ImageIO
import SwiftUI

/// Images waiting to be inserted, and where.
struct PendingImages: Identifiable {
    let id = UUID()
    var urls: [URL]
    /// Character position to insert at, or nil for the cursor.
    var location: Int?
}

/// Asks how to add images (optimized for web, pre-selected, or full
/// resolution) and an optional description, then imports them.
struct InsertImageSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let pending: PendingImages
    let item: ContentItem
    let onInsert: ([String], Int?) -> Void

    @AppStorage("imageInsertMode") private var mode = ImageImporter.Mode.optimized
    @State private var alt = ""
    @State private var isWorking = false
    @State private var error: String?

    private var count: Int { pending.urls.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(count == 1 ? "Insert Image" : "Insert \(count) Images")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(pending.urls, id: \.self) { url in
                        ImageThumbnail(url: url)
                    }
                }
            }
            .frame(height: 96)

            if count == 1 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description")
                        .font(.callout.weight(.medium))
                    TextField("Description", text: $alt, prompt: Text("What the image shows"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                    Text("Read aloud by screen readers and shown as the caption in the lightbox.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Size", selection: $mode) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Optimized for web (recommended)")
                    Text("Up to \(ImageImporter.largeMaxPixels) px in the lightbox and \(ImageImporter.inlineMaxPixels) px on the page. Smaller files and faster pages. Location data is removed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .tag(ImageImporter.Mode.optimized)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Full resolution")
                    Text("The original file as it is. Larger files and slower pages. HEIC photos are converted to JPEG so browsers can show them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .tag(ImageImporter.Mode.original)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if isWorking {
                    ProgressView().controlSize(.small)
                    Text(mode == .optimized ? "Optimizing…" : "Copying…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isWorking)
                Button("Insert", action: insert)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWorking)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            if count == 1, let url = pending.urls.first { alt = ImageImporter.defaultAlt(for: url) }
        }
    }

    private func insert() {
        guard let root = model.site?.root else { return }
        let (folder, prefix) = ImageImporter.location(for: item, root: root)
        let items = pending.urls.map { url in
            ImageImporter.Item(source: url, alt: count == 1 ? alt : ImageImporter.defaultAlt(for: url))
        }
        let mode = mode
        let location = pending.location
        error = nil
        isWorking = true
        Task {
            do {
                let blocks = try await Task.detached(priority: .userInitiated) {
                    try ImageImporter.importImages(items, folder: folder, urlPrefix: prefix, mode: mode)
                }.value
                isWorking = false
                dismiss()
                onInsert(blocks, location)
                model.showToast(count == 1 ? "Image added." : "\(count) images added.")
            } catch {
                isWorking = false
                self.error = error.localizedDescription
            }
        }
    }
}

/// A small preview of an image file, made without loading the full image.
struct ImageThumbnail: View {
    let url: URL
    var size: CGFloat = 96
    /// True to fill a square (cropping); false to show the whole image at its
    /// own shape, fitting inside the square.
    var fill = true
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                if fill {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
                } else {
                    // The rounded corners and border hug the image itself.
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                        .frame(maxWidth: size, maxHeight: size)
                }
            } else {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .help(url.lastPathComponent)
        // Reloads when the file is edited.
        .task(id: (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) {
            let url = url
            let size = size
            let cgImage = await Task.detached { () -> CGImage? in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: size * 2,
                ]
                return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            }.value
            if let cgImage { image = NSImage(cgImage: cgImage, size: .zero) }
        }
    }
}
