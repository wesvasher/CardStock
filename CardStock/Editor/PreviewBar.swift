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
/// round Back and Forward buttons, the page's built file, a Desktop /
/// iPhone switch, and the full device menu.
struct PreviewBar: View {
    @Binding var device: PreviewDevice
    let navigator: PreviewNavigator

    /// Height of the window toolbar's buttons, which this bar matches.
    static let controlHeight: CGFloat = 36
    static let barHeight: CGFloat = 52

    /// The Desktop / iPhone switch: Fit to Window or iPhone 17. Other
    /// devices chosen from the menu leave both unselected.
    private var options: [GlassSegmentedPicker<PreviewDevice>.Option] {
        [.init(.fit, "Desktop", systemImage: "desktopcomputer"),
         .init(.iphone, "iPhone", systemImage: "iphone")]
    }

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

                GlassSegmentedPicker(selection: $device, options: options, height: Self.controlHeight)
                    .help("Switch between a desktop and an iPhone 17 view")

                Menu {
                    Picker("Preview Device", selection: $device) {
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
                    Image(systemName: device.systemImage)
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: Self.controlHeight, height: Self.controlHeight)
                        .contentShape(Circle())
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .roundGlass(Self.controlHeight)
                .help("Preview as \(device.name)")
            }
            .padding(.horizontal, 10)
            .frame(height: Self.barHeight)
        }
    }

    private func roundButton(_ symbol: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: Self.controlHeight, height: Self.controlHeight)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.5))
        .roundGlass(Self.controlHeight, interactive: enabled)
        .disabled(!enabled)
        .help(help)
    }
}
