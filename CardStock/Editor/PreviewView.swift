import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Shows a page of the site as it will look when published, rendered from
/// the in-memory (possibly unsaved) content.
struct PreviewView: NSViewRepresentable {
    var site: Site
    var path: String
    var revision: Int
    var userAgent: String
    /// Below 1 when simulating a screen wider than the space available.
    var zoom: Double = 1
    /// Gets the web view so the browser bar can go back and forward.
    var navigator: PreviewNavigator?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(context.coordinator.handler, forURLScheme: PreviewSchemeHandler.scheme)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        navigator?.attach(webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let c = context.coordinator
        c.handler.site = site
        c.navigator = navigator
        if webView.pageZoom != zoom {
            webView.pageZoom = zoom
        }
        if webView.customUserAgent != userAgent {
            webView.customUserAgent = userAgent
            if c.loadedPath != nil {
                c.loadedPath = path
                c.loadedRevision = revision
                webView.load(URLRequest(url: PreviewSchemeHandler.url(for: path)))
                return
            }
        }
        if c.loadedPath != path {
            c.loadedPath = path
            c.loadedRevision = revision
            webView.load(URLRequest(url: PreviewSchemeHandler.url(for: path)))
        } else if c.loadedRevision != revision {
            c.loadedRevision = revision
            webView.reload()
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let handler = PreviewSchemeHandler()
        var loadedPath: String?
        var loadedRevision = 0
        var navigator: PreviewNavigator?

        /// The bar follows the preview that loaded a page last, so a web
        /// view being replaced (switching views or devices) can't leave it
        /// showing, and editing, an old address.
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            navigator?.attach(webView)
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = action.request.url else { return .cancel }
            if url.scheme == PreviewSchemeHandler.scheme {
                // Links meant for a new tab (like RSS) open in the preview itself.
                if action.targetFrame == nil {
                    webView.load(action.request)
                    return .cancel
                }
                return .allow
            }
            // Embedded players and forms (Vimeo, mailing list services) load
            // in their frames.
            if let frame = action.targetFrame, !frame.isMainFrame, url.scheme == "https" || url.scheme == "about" {
                return .allow
            }
            // Links leaving the site open in the default browser.
            if action.navigationType == .linkActivated {
                NSWorkspace.shared.open(url)
            }
            return .cancel
        }
    }
}

/// Serves `cardstock-preview://site/<path>` from the site folder and renderer.
@MainActor
final class PreviewSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "cardstock-preview"
    var site: Site?

    static func url(for path: String) -> URL {
        URL(string: "\(scheme)://site\(path)")!
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let encodedPath = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? "/"
        let path = encodedPath.removingPercentEncoding ?? encodedPath
        var (data, mime, status) = respond(to: path.isEmpty ? "/" : path)
        var headers = ["Content-Type": mime, "Cache-Control": "no-store", "Accept-Ranges": "bytes"]
        // Video needs byte ranges: WebKit asks for parts of the file.
        if status == 200, let header = task.request.value(forHTTPHeaderField: "Range"),
           let range = Self.byteRange(header, length: data.count) {
            headers["Content-Range"] = "bytes \(range.lowerBound)-\(range.upperBound - 1)/\(data.count)"
            data = data.subdata(in: range)
            status = 206
        }
        headers["Content-Length"] = String(data.count)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    /// The bytes a `Range: bytes=a-b` header asks for (also `a-` and `-n`,
    /// the last n bytes), within a file of `length` bytes.
    nonisolated static func byteRange(_ header: String, length: Int) -> Range<Int>? {
        let spec = header.trimmingCharacters(in: .whitespaces)
        guard length > 0, spec.lowercased().hasPrefix("bytes="), !spec.contains(",") else { return nil }
        let parts = spec.dropFirst(6).split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return nil }
        if parts[0].isEmpty {
            guard let n = Int(parts[1]), n > 0 else { return nil }
            return max(length - n, 0)..<length
        }
        guard let start = Int(parts[0]), start < length else { return nil }
        let end = parts[1].isEmpty ? length - 1 : min(Int(parts[1]) ?? length - 1, length - 1)
        guard end >= start else { return nil }
        return start..<(end + 1)
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    private func respond(to path: String) -> (Data, String, Int) {
        guard let site else { return (Data(), "text/plain", 404) }
        let root = site.root

        if path == ModelEmbed.scriptPath, let script = ModelEmbed.bundledScript, let data = try? Data(contentsOf: script) {
            return (data, "text/javascript; charset=utf-8", 200)
        }
        if path.hasPrefix("/assets/") {
            if let file = fileResponse(root.appending(path: "theme"), path) { return file }
        } else if path.hasPrefix("/media/") {
            if let file = fileResponse(root, path) { return file }
        }

        do {
            let renderer = try SiteRenderer(site: site, includeDrafts: true)
            if let html = renderer.render(path: path) {
                let mime = path.hasSuffix(".xml") ? "application/xml"
                    : path.hasSuffix(".json") ? "application/json; charset=utf-8"
                    : "text/html; charset=utf-8"
                return (Data(VideoEmbed.previewPlaceholders(in: html).utf8), mime, 200)
            }
            if let file = fileResponse(root.appending(path: "static"), path) { return file }
            let notFound = renderer.render(path: "/404.html") ?? "<h1>Not found</h1>"
            return (Data(notFound.utf8), "text/html; charset=utf-8", 404)
        } catch {
            let html = """
            <body style="font: 14px -apple-system, sans-serif; padding: 2rem; color: #b00">
            <h2>The preview couldn't be rendered</h2><p>\(escapeHTML(error.localizedDescription))</p></body>
            """
            return (Data(html.utf8), "text/html; charset=utf-8", 500)
        }
    }

    /// Reads a file under `base`, refusing paths that escape it.
    private func fileResponse(_ base: URL, _ path: String) -> (Data, String, Int)? {
        let file = base.appending(path: String(path.dropFirst())).standardizedFileURL
        guard file.path.hasPrefix(base.standardizedFileURL.path + "/"),
              let data = try? Data(contentsOf: file) else { return nil }
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return (data, mime, 200)
    }
}
