import AppKit
import SwiftUI

/// A logo image and its size, used by the top bar and the footer: Choose
/// Image… (from Files or the Mac), then either Height (SVGs, or images whose
/// size can't be read) or Width × Height with Keep proportions and Actual
/// Size.
struct LogoImageRows: View {
    @Environment(AppModel.self) private var model
    @Binding var image: String
    @Binding var width: Int
    @Binding var height: Int
    /// The Choose sheet's title.
    var sheetTitle = "Choose a Logo"
    /// The height a newly chosen logo starts at. nil starts images at their
    /// actual size (SVGs at 100 px tall).
    var startHeight: Int?
    @AppStorage("logoKeepProportions") private var keepProportions = true
    @State private var choosing = false

    private var hasImage: Bool { !image.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        LabeledContent("Image") {
            HStack(spacing: 8) {
                if hasImage {
                    thumbnail
                    Text(image)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Change…") { choosing = true }
                    Button("Remove") { image = "" }
                } else {
                    Button("Choose Image…") { choosing = true }
                }
            }
        }
        .sheet(isPresented: $choosing) {
            InsertFromFilesSheet(title: sheetTitle,
                                 message: "Pick an image from your site's Files, or choose one from your Mac to copy it in.",
                                 actionTitle: "Choose",
                                 allowsMacFiles: true) { file in
                choose(file)
            }
        }

        if hasImage && natural == nil {
            // SVGs (and images whose size can't be read): height only.
            LabeledContent("Height") {
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 6) {
                        PixelField(label: "Height", value: $height)
                        Text("px").foregroundStyle(.secondary)
                    }
                    Text(isSVG
                         ? "SVG images stay sharp at any size and have no size in pixels of their own, so just set the height. The width follows the logo's shape."
                         : "CardStock can't read this image's size, so just set the height. The width follows the image's shape.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if hasImage {
            LabeledContent("Size") {
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 6) {
                        PixelField(label: "Width", value: widthBinding)
                        Text("×").foregroundStyle(.secondary)
                        PixelField(label: "Height", value: heightBinding)
                        Text("px").foregroundStyle(.secondary)
                    }
                    HStack(spacing: 10) {
                        Toggle("Keep proportions", isOn: $keepProportions)
                        if let natural {
                            Button("Actual Size (\(natural.width) × \(natural.height))") {
                                width = natural.width
                                height = natural.height
                            }
                            .buttonStyle(.link)
                        }
                    }
                    .font(.caption)
                    .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = imageURL, let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
        }
    }

    /// The image file in the site folder, for a /media/... address.
    private var imageURL: URL? {
        guard let root = model.site?.root else { return nil }
        var path = image.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty, !path.contains("://") else { return nil }
        if path.hasPrefix("/") { path.removeFirst() }
        return root.appending(path: path)
    }

    private var isSVG: Bool { image.lowercased().hasSuffix(".svg") }

    /// The image's own size in pixels, when it can be read (not for SVG).
    private var natural: (width: Int, height: Int)? {
        isSVG ? nil : imageURL.flatMap(ImageImporter.pixelSize(of:))
    }

    /// Width, changing the height to match when keeping proportions.
    private var widthBinding: Binding<Int> {
        Binding(get: { width }, set: { new in
            width = max(new, 0)
            if keepProportions, let natural, natural.width > 0, new > 0 {
                height = Int((Double(new) * Double(natural.height) / Double(natural.width)).rounded())
            }
        })
    }

    private var heightBinding: Binding<Int> {
        Binding(get: { height }, set: { new in
            height = max(new, 0)
            if keepProportions, let natural, natural.height > 0, new > 0 {
                width = Int((Double(new) * Double(natural.width) / Double(natural.height)).rounded())
            }
        })
    }

    /// Uses a file as the logo, at its actual size or scaled to `startHeight`.
    private func choose(_ file: MediaFile) {
        image = "/" + file.path
        let url = model.site?.root.appending(path: file.path)
        if !file.path.lowercased().hasSuffix(".svg"), let url, let size = ImageImporter.pixelSize(of: url),
           size.height > 0 {
            if let startHeight {
                height = startHeight
                width = Int((Double(startHeight) * Double(size.width) / Double(size.height)).rounded())
            } else {
                width = size.width
                height = size.height
            }
        } else {
            // No size to start from (e.g. SVG): width follows the shape.
            width = 0
            height = startHeight ?? 100
        }
    }
}

/// A small number field for a size in pixels.
struct PixelField: View {
    let label: String
    @Binding var value: Int
    var width: CGFloat = 64

    var body: some View {
        TextField(label, value: $value, format: .number.grouping(.never))
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: width)
            .accessibilityLabel(label)
    }
}
