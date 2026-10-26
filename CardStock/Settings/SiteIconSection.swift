import AppKit
import SwiftUI

/// Configuration → Site Details → Site Icon: one square image for home
/// screens on iPhone, iPad and Android, plus an optional favicon of its own.
struct SiteIconSection: View {
    @Environment(AppModel.self) private var model

    private var config: SiteConfig { model.site?.config ?? SiteConfig() }
    private var icon: SiteConfig.Icon { config.icon }

    var body: some View {
        Section {
            LogoFileRow(title: "Image", path: binding(\.image),
                        emptyText: "None", sheetTitle: "Choose a Site Icon")
            if icon.hasImage {
                SiteIconPreview(icon: icon, title: icon.shownName(siteTitle: config.title))
                ColorPicker(selection: Binding(
                    get: { Color(hex: icon.backgroundHex) ?? .white },
                    set: { binding(\.background).wrappedValue = $0.hexString }),
                            supportsOpacity: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Background")
                        Text("Fills any transparent parts on iPhone and iPad, and the space around the icon on Android.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                TextField("Name on home screen", text: binding(\.name), prompt: Text(config.title))
                    .help("Shown under the icon. Keep it short; leave empty to use the site title.")
            }

            Toggle(isOn: binding(\.customFavicon)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use a different favicon")
                    Text(icon.customFavicon
                         ? "The browser tab shows the image below, as it is. GIF, PNG, ICO and SVG all work."
                         : "Off: the browser tab shows a small version of the site icon.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            if icon.customFavicon {
                LogoFileRow(title: "Favicon", path: binding(\.favicon),
                            emptyText: icon.hasImage ? "Uses the site icon" : "None",
                            sheetTitle: "Choose a Favicon")
            }
        } header: {
            Text("Site Icon")
        } footer: {
            Text("When someone adds your site to their home screen on an iPhone, iPad or Android phone or tablet, this is its icon. Use a square image, ideally 1024 × 1024 pixels. CardStock makes every size those devices need when you publish.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<SiteConfig.Icon, T>) -> Binding<T> {
        Binding(
            get: { icon[keyPath: keyPath] },
            set: { newValue in
                guard var updated = model.site?.config else { return }
                updated.icon[keyPath: keyPath] = newValue
                model.updateConfig(updated)
            })
    }
}

/// The icon as an iPhone shows it (rounded square), as Android shows it
/// (cropped to a circle) and in a browser tab, drawn the same way as the
/// published files.
private struct SiteIconPreview: View {
    @Environment(AppModel.self) private var model
    let icon: SiteConfig.Icon
    let title: String
    @State private var images: [String: NSImage] = [:]

    private var key: String {
        [icon.image, icon.backgroundHex, icon.customFaviconPath ?? ""].joined(separator: "|")
    }

    var body: some View {
        LabeledContent("Preview") {
            HStack(alignment: .top, spacing: 22) {
                tile("iPhone, iPad") {
                    picture(SiteIcon.appleTouch.file)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                tile("Android") {
                    picture(SiteIcon.maskable.file)
                        .clipShape(Circle())
                }
                tile("Browser tab") {
                    HStack(spacing: 6) {
                        picture("favicon")
                            .frame(width: 16, height: 16)
                        Text(title)
                            .font(.caption)
                            .lineLimit(1)
                            .frame(maxWidth: 90, alignment: .leading)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    .frame(height: 60)
                }
            }
        }
        .task(id: key) { load() }
    }

    private func tile(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 6) {
            content()
                .frame(height: 60)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func picture(_ name: String) -> some View {
        if let image = images[name] {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: name == "favicon" ? 16 : 60, height: name == "favicon" ? 16 : 60)
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
                .frame(width: name == "favicon" ? 16 : 60, height: name == "favicon" ? 16 : 60)
        }
    }

    private func load() {
        guard let root = model.site?.root else { return }
        var result: [String: NSImage] = [:]
        if let url = SiteIcon.sourceURL(icon.image, root: root), let source = SiteIcon.loadImage(url) {
            for size in [SiteIcon.appleTouch, SiteIcon.maskable, SiteIcon.favicon] {
                if let cg = SiteIcon.render(source, size: size, background: icon.background) {
                    result[size.file] = NSImage(cgImage: cg, size: NSSize(width: size.pixels, height: size.pixels))
                }
            }
            result["favicon"] = result[SiteIcon.favicon.file]
        }
        if let path = icon.customFaviconPath, let url = SiteIcon.sourceURL(path, root: root),
           let custom = NSImage(contentsOf: url) {
            result["favicon"] = custom
        }
        images = result
    }
}
