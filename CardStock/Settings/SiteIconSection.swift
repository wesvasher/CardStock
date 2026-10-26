import AppKit
import SwiftUI

/// Configuration → Site Details → Site Icon: one square image for home
/// screens on iPhone, iPad and Android, plus an optional favicon of its own
/// and an optional dark mode favicon.
struct SiteIconSection: View {
    @Environment(AppModel.self) private var model
    @State private var images = IconImages()

    private var config: SiteConfig { model.site?.config ?? SiteConfig() }
    private var icon: SiteConfig.Icon { config.icon }

    var body: some View {
        Section {
            LogoFileRow(title: "Image", path: binding(\.image),
                        emptyText: "None", sheetTitle: "Choose a Site Icon")
            if icon.hasImage {
                LabeledContent("Home screens") {
                    HStack(alignment: .top, spacing: 22) {
                        tile("iPhone, iPad") {
                            picture(images.appleTouch, size: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }
                        tile("Android") {
                            picture(images.maskable, size: 60)
                                .clipShape(Circle())
                        }
                    }
                }
                ColorPicker(selection: Binding(
                    get: { Color(hex: icon.backgroundHex) ?? .white },
                    set: { binding(\.background).wrappedValue = $0.hexString }),
                            supportsOpacity: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Background")
                        caption("Fills any transparent parts on iPhone and iPad, and the space around the icon on Android.")
                    }
                }
                TextField("Name on home screen", text: binding(\.name), prompt: Text(config.title))
                    .help("Shown under the icon. Keep it short; leave empty to use the site title.")
            }
        } header: {
            Text("Site Icon")
        } footer: {
            caption("When someone adds your site to their home screen on an iPhone, iPad or Android phone or tablet, this is its icon. Use a square image, ideally 1024 × 1024 pixels. CardStock makes every size those devices need when you publish.")
        }
        .task(id: loadKey) { images = IconImages.load(icon, root: model.site?.root) }

        Section {
            LogoFileRow(title: "Favicon", path: binding(\.favicon),
                        emptyText: icon.hasImage ? "Made from the site icon" : "None",
                        sheetTitle: "Choose a Favicon")

            Toggle(isOn: binding(\.darkMode)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dark mode favicon")
                    caption("Browsers on a device set to dark show this version, such as one with light lines that stand out on a dark tab bar.")
                }
            }
            .toggleStyle(.switch)
            if icon.darkMode {
                if icon.customFaviconPath != nil {
                    LogoFileRow(title: "Dark favicon", path: binding(\.darkFavicon),
                                emptyText: "Uses the favicon", sheetTitle: "Choose a Dark Mode Favicon")
                } else {
                    LogoFileRow(title: "Dark mode icon", path: binding(\.darkImage),
                                emptyText: "Uses the site icon", sheetTitle: "Choose a Dark Mode Icon")
                }
            }

            if images.favicon != nil {
                LabeledContent("Browser tabs") {
                    HStack(spacing: 14) {
                        tile("Light") {
                            BrowserTab(icon: images.favicon, title: config.title, dark: false)
                        }
                        tile("Dark") {
                            BrowserTab(icon: images.faviconDark ?? images.favicon, title: config.title, dark: true)
                        }
                    }
                }
            }
        } header: {
            Text("Favicon")
        } footer: {
            caption("The small icon in browser tabs, bookmarks and history. Choose any image (GIF, PNG, ICO and SVG all work) and it's used as it is; without one, CardStock makes a small version of the site icon. Home screen icons can't have a dark version: iPhone, iPad and Android show the same icon in light and dark mode.")
        }
    }

    /// Changes whenever a preview would look different.
    private var loadKey: String {
        [icon.image, icon.backgroundHex, icon.customFaviconPath ?? "", icon.darkImagePath ?? "",
         icon.darkFaviconPath ?? ""].joined(separator: "|")
    }

    private func tile(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 6) {
            content()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func picture(_ image: NSImage?, size: CGFloat) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
                .frame(width: size, height: size)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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

/// The preview images, drawn the same way as the published files (custom
/// favicons are shown as they are).
private struct IconImages {
    var appleTouch: NSImage?
    var maskable: NSImage?
    var favicon: NSImage?
    /// nil when there's no dark favicon (the regular one is used).
    var faviconDark: NSImage?

    @MainActor
    static func load(_ icon: SiteConfig.Icon, root: URL?) -> IconImages {
        guard let root else { return IconImages() }
        func made(_ path: String?, _ size: SiteIcon.Size) -> NSImage? {
            guard let path, let url = SiteIcon.sourceURL(path, root: root), let source = SiteIcon.loadImage(url),
                  let cg = SiteIcon.render(source, size: size, background: icon.background) else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: size.pixels, height: size.pixels))
        }
        func file(_ path: String?) -> NSImage? {
            guard let path, let url = SiteIcon.sourceURL(path, root: root) else { return nil }
            return NSImage(contentsOf: url)
        }
        let image = icon.hasImage ? icon.image : nil
        var result = IconImages()
        result.appleTouch = made(image, SiteIcon.appleTouch)
        result.maskable = made(image, SiteIcon.maskable)
        result.favicon = icon.customFaviconPath != nil ? file(icon.customFaviconPath) : made(image, SiteIcon.favicon)
        result.faviconDark = icon.darkFaviconPath != nil ? file(icon.darkFaviconPath) : made(icon.darkImagePath, SiteIcon.faviconDark)
        return result
    }
}

/// A browser tab in a strip of tab bar, light or dark, with the favicon and
/// the site's title.
private struct BrowserTab: View {
    let icon: NSImage?
    let title: String
    let dark: Bool

    private var bar: Color { dark ? Color(white: 0.12) : Color(white: 0.88) }
    private var tab: Color { dark ? Color(white: 0.24) : .white }
    private var text: Color { dark ? Color(white: 0.92) : Color(white: 0.12) }

    var body: some View {
        HStack(spacing: 7) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    RoundedRectangle(cornerRadius: 3).fill(text.opacity(0.2))
                }
            }
            .frame(width: 16, height: 16)
            Text(title.isEmpty ? "My Site" : title)
                .font(.system(size: 11))
                .foregroundStyle(text)
                .lineLimit(1)
                .frame(maxWidth: 110, alignment: .leading)
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(text.opacity(0.5))
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(tab, in: UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8))
        .padding(.top, 6)
        .padding(.horizontal, 10)
        .background(bar, in: RoundedRectangle(cornerRadius: 8))
        .environment(\.colorScheme, dark ? .dark : .light)
    }
}
