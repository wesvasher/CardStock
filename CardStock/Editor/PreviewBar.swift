import SwiftUI
import WebKit

/// Follows the preview's web view so the browser bar can show its address
/// and go back and forward.
@MainActor @Observable
final class PreviewNavigator {
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    /// The address of the page shown, such as `/blog/pages/hello-world/`.
    private(set) var address = "/"

    @ObservationIgnored private weak var webView: WKWebView?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    func attach(_ webView: WKWebView) {
        guard webView !== self.webView else { return }
        self.webView = webView
        // WKWebView reports these changes on the main thread.
        observations = [
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.canGoBack = view.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.canGoForward = view.canGoForward }
            },
            webView.observe(\.url, options: [.initial, .new]) { [weak self] view, _ in
                MainActor.assumeIsolated {
                    guard let url = view.url, url.scheme == PreviewSchemeHandler.scheme else { return }
                    let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.path ?? "/"
                    self?.address = path.isEmpty ? "/" : path
                }
            },
        ]
    }

    /// The built file the page comes from, such as `public/index.html`
    /// for the Home page or `public/blog/pages/trip/index.html` for a post.
    var builtFile: String { Self.builtFile(for: address) }

    nonisolated static func builtFile(for address: String) -> String {
        let path = address.hasPrefix("/") ? address : "/" + address
        return "public" + path + (path.hasSuffix("/") ? "index.html" : "")
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
}

/// The bar above the preview, sized and styled like the window's toolbar:
/// round Back and Forward buttons, the page's built file, a pencil that
/// edits the page shown, and a Desktop / iPhone / ⋯ switch.
struct PreviewBar: View {
    @Environment(AppModel.self) private var model
    @Binding var device: PreviewDevice
    let navigator: PreviewNavigator

    /// Height of the window toolbar's buttons, which this bar matches.
    static let controlHeight: CGFloat = 36
    static let barHeight: CGFloat = 52

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 8) {
                roundButton("chevron.left", help: "Back", enabled: navigator.canGoBack, action: navigator.goBack)
                roundButton("chevron.right", help: "Forward", enabled: navigator.canGoForward, action: navigator.goForward)

                Text(navigator.builtFile)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.leading, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help("\(navigator.builtFile) · published at \(navigator.address)")
                    .layoutPriority(-1)

                editButton

                DeviceSwitch(device: $device, height: Self.controlHeight)
            }
            .padding(.horizontal, 10)
            .frame(height: Self.barHeight)
        }
    }

    /// What the pencil opens for the page in the preview.
    private enum EditTarget {
        case page(ContentItem)
        /// A collection's main page that has no file yet: opening it makes one.
        case mainPage(ContentCollection)
    }

    private var editTarget: EditTarget? {
        guard let site = model.site else { return nil }
        if let page = site.item(atAddress: navigator.address) { return .page(page) }
        var path = navigator.address.hasSuffix("/index.html") ? String(navigator.address.dropLast("index.html".count)) : navigator.address
        if !path.hasSuffix("/") { path += "/" }
        if let collection = site.config.collections.first(where: { $0.mainPath == path }) { return .mainPage(collection) }
        return nil
    }

    /// Pencil: opens the page shown in the preview in the editor. It's
    /// dimmed, not disabled, when there's nothing to open, so its tooltip
    /// still says why (disabled buttons show none).
    private var editButton: some View {
        let target = editTarget
        let editing: ContentItem? = if case .page(let page) = target, model.selection == .pages,
                                       page.id == model.selectedPageID { page } else { nil }
        let help: String
        switch target {
        case .page(let page):
            help = editing != nil ? "“\(page.title)” is open in the editor" : "Edit “\(page.title)”"
        case .mainPage(let collection):
            help = "Edit the \(collection.name) main page: the text above its list"
        case nil:
            help = "This page is made by CardStock (like tag pages and previews), so it has no text of its own to edit"
        }
        return roundButton("pencil", help: help, enabled: target != nil && editing == nil, disables: false) {
            switch target {
            case .page(let page): if editing == nil { model.selection = .item(page.id) }
            case .mainPage(let collection): model.openMainPage(of: collection)
            case nil: break
            }
        }
    }

    private func roundButton(_ symbol: String, help: String, enabled: Bool, disables: Bool = true,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: Self.controlHeight, height: Self.controlHeight)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.5))
        .roundGlass(Self.controlHeight, interactive: enabled)
        .disabled(disables && !enabled)
        .help(help)
    }
}

/// Desktop, iPhone and ⋯ in one glass switch. Desktop is Fit to Window and
/// iPhone is iPhone 17; ⋯ opens every size, and is the selected part while
/// one of those other sizes is shown.
private struct DeviceSwitch: View {
    @Binding var device: PreviewDevice
    let height: CGFloat
    @Namespace private var namespace

    private let inset: CGFloat = 3
    private static let quick: [(PreviewDevice, String, String)] = [
        (.fit, "Desktop", "desktopcomputer"),
        (.iphone, "iPhone", "iphone"),
    ]

    private var isOtherSize: Bool { !Self.quick.contains { $0.0 == device } }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.quick, id: \.0) { value, title, symbol in
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) { device = value }
                } label: {
                    segmentLabel(symbol, selected: device == value)
                }
                .buttonStyle(.plain)
                .help(title)
                .accessibilityLabel(title)
                .accessibilityAddTraits(device == value ? .isSelected : [])
            }
            Menu {
                Picker("Preview Device", selection: Binding(
                    get: { device },
                    set: { new in withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) { device = new } })) {
                    ForEach(PreviewDevice.Group.allCases, id: \.self) { group in
                        Section(group.rawValue) {
                            ForEach(PreviewDevice.allCases.filter { $0.group == group }) { d in
                                Label(d.menuTitle, systemImage: d.systemImage).tag(d)
                            }
                        }
                    }
                }
                .pickerStyle(.inline)
            } label: {
                segmentLabel("ellipsis", selected: isOtherSize)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
            .help(isOtherSize ? "Previewing as \(device.name). Click for more sizes." : "More sizes: laptops, iPads, other phones")
            .accessibilityLabel(isOtherSize ? "More sizes, \(device.name)" : "More sizes")
            .accessibilityAddTraits(isOtherSize ? .isSelected : [])
        }
        .padding(inset)
        .frame(height: height)
        .glassEffect(.regular.interactive(), in: .capsule)
        .fixedSize(horizontal: true, vertical: false)
    }

    /// An icon with the sliding tinted pill behind it when selected, like
    /// `GlassSegmentedPicker`.
    private func segmentLabel(_ symbol: String, selected: Bool) -> some View {
        Image(systemName: symbol)
            .font(.callout.weight(selected ? .semibold : .medium))
            .foregroundStyle(selected ? Color.white : Color.primary)
            .frame(width: 22)
            .padding(.horizontal, 10)
            // A set height, not "fill": the menu's label sizes itself to its
            // content, so ⋯'s pill would come out shorter than the others.
            .frame(height: height - inset * 2)
            .background {
                if selected {
                    Capsule()
                        .fill(Color.accentColor.opacity(0.85))
                        .glassEffect(.regular.tint(.accentColor).interactive(), in: .capsule)
                        .matchedGeometryEffect(id: "selection", in: namespace)
                        .shadow(color: Color.accentColor.opacity(0.35), radius: 4, y: 1)
                }
            }
            .contentShape(Capsule())
            .scaleEffect(selected ? 1 : 0.97)
    }
}
