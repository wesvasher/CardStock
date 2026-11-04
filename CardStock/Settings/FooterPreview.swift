import SwiftUI
import WebKit

/// The live footer previews at the top of Configuration → Footer: the footer
/// as a computer shows it and as a phone does, drawn by the site's own
/// theme from `/_footer/` (only the footer shows there).
struct FooterPreviewPanel: View {
    @Environment(AppModel.self) private var model
    @AppStorage("footerPreviewShown") private var shown = true
    @State private var revision = 0

    /// The screen widths shown, in CSS pixels.
    static let desktopWidth = 1200.0
    static let phoneWidth = 390.0
    static let phoneZoom = 0.6

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { shown.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(shown ? 90 : 0))
                        .font(.caption.weight(.semibold))
                    Text("Preview").font(.headline)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(shown ? "Hide the preview" : "Show the preview")

            if shown, let site = model.site {
                previewRow(title: "Computer", systemImage: "desktopcomputer") {
                    GeometryReader { geo in
                        FooterSnippetView(site: site, revision: revision,
                                          zoom: min(geo.size.width / Self.desktopWidth, 1),
                                          userAgent: PreviewDevice.desktop.userAgent,
                                          height: $desktopHeight)
                    }
                    .frame(height: desktopHeight)
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
                }
                previewRow(title: "Phone", systemImage: "iphone") {
                    FooterSnippetView(site: site, revision: revision, zoom: Self.phoneZoom,
                                      userAgent: PreviewDevice.iphone.userAgent,
                                      height: $phoneHeight)
                        .frame(width: Self.phoneWidth * Self.phoneZoom, height: phoneHeight)
                        .background(.background)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.separator))
                }
                Text("Your footer as visitors see it, from your theme. Drop menus open when you click them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        // Wait for a pause in typing before refreshing.
        .task(id: model.revision) {
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled { revision = model.revision }
        }
    }

    @State private var desktopHeight = 60.0
    @State private var phoneHeight = 160.0

    private func previewRow<Content: View>(title: String, systemImage: String,
                                           @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            content()
        }
    }
}

/// A web view showing the footer scaled by `zoom` (so a frame of W points
/// lays the page out W / zoom CSS pixels wide), reporting its height so the frame fits it. Links don't
/// navigate; drop menus open and close.
struct FooterSnippetView: NSViewRepresentable {
    var site: Site
    var revision: Int
    var zoom: Double
    var userAgent: String
    @Binding var height: Double

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(context.coordinator.handler, forURLScheme: PreviewSchemeHandler.scheme)
        // Reports the bottom of the footer whenever it changes size (an open
        // menu makes it taller on phones).
        let script = """
            (function () {
              function send() {
                var f = document.querySelector('.site-footer');
                var h = f ? f.getBoundingClientRect().bottom + window.scrollY : 0;
                window.webkit.messageHandlers.footerHeight.postMessage(Math.ceil(h));
              }
              var f = document.querySelector('.site-footer');
              if (f && window.ResizeObserver) new ResizeObserver(send).observe(f);
              send();
            })();
            """
        config.userContentController.addUserScript(
            WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        config.userContentController.add(WeakMessageHandler(context.coordinator), name: "footerHeight")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let c = context.coordinator
        c.handler.site = site
        c.zoom = zoom
        c.height = $height
        if webView.pageZoom != zoom { webView.pageZoom = zoom }
        if webView.customUserAgent != userAgent { webView.customUserAgent = userAgent }
        if !c.loaded {
            c.loaded = true
            c.revision = revision
            webView.load(URLRequest(url: PreviewSchemeHandler.url(for: SiteRenderer.footerPreviewPath)))
        } else if c.revision != revision {
            c.revision = revision
            webView.reload()
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "footerHeight")
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let handler = PreviewSchemeHandler()
        var loaded = false
        var revision = 0
        var zoom = 1.0
        var height: Binding<Double>

        init(height: Binding<Double>) { self.height = height }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let css = message.body as? Double ?? (message.body as? Int).map(Double.init), css > 0 else { return }
            let points = (css * zoom).rounded(.up)
            if abs(height.wrappedValue - points) > 0.5 { height.wrappedValue = points }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            // Only the footer page itself (and its reloads); links stay put.
            guard let url = action.request.url, url.scheme == PreviewSchemeHandler.scheme,
                  url.path == SiteRenderer.footerPreviewPath || url.path + "/" == SiteRenderer.footerPreviewPath,
                  action.navigationType != .linkActivated else {
                return action.targetFrame?.isMainFrame == false ? .allow : .cancel
            }
            return .allow
        }
    }
}

/// Passes script messages on without the content controller keeping the
/// coordinator alive.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?
    init(_ target: any WKScriptMessageHandler) { self.target = target }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
