import AppKit
import SwiftUI
import WebKit

/// The Help Center list in the center column. The chosen article is shown
/// in the right column by `HelpArticleView`.
struct HelpCenterView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    private var results: [HelpArticle] { HelpCenter.articles.filter { $0.matches(query) } }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Help Center")
                    .font(.title2.bold())
                Text("Step-by-step guides and answers to common questions.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search help", text: $query)
                        .textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Clear search")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(20)

            Divider()

            if results.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $model.helpArticleID) {
                    ForEach(HelpCategory.allCases, id: \.self) { category in
                        let articles = results.filter { $0.category == category }
                        if !articles.isEmpty {
                            Section(category.rawValue) {
                                ForEach(articles) { article in
                                    HelpRow(article: article)
                                        .tag(article.id)
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            if model.helpArticleID == nil { model.helpArticleID = HelpCenter.articles.first?.id }
        }
    }
}

private struct HelpRow: View {
    let article: HelpArticle

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(article.title)
            if !article.summary.isEmpty {
                Text(article.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }
}

/// The selected help article, in the right column.
struct HelpArticleView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let id = model.helpArticleID, let article = HelpCenter.article(id) {
            HelpWebView(article: article,
                        onArticle: { model.helpArticleID = $0 },
                        onAppLink: { model.openAppLink($0) })
        } else {
            ContentUnavailableView("Choose an Article", systemImage: "questionmark.circle",
                                   description: Text("Pick a guide or question from the Help Center."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Shows an article's HTML. Article links switch articles, `cardstock:` links
/// jump to a part of the app, and web links open in the default browser.
private struct HelpWebView: NSViewRepresentable {
    let article: HelpArticle
    let onArticle: (String) -> Void
    let onAppLink: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let c = context.coordinator
        c.onArticle = onArticle
        c.onAppLink = onAppLink
        guard c.loadedID != article.id else { return }
        c.loadedID = article.id
        webView.loadHTMLString(HelpCenter.html(for: article), baseURL: nil)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedID: String?
        var onArticle: (String) -> Void = { _ in }
        var onAppLink: (String) -> Void = { _ in }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard action.navigationType == .linkActivated, let url = action.request.url else { return .allow }
            switch url.scheme?.lowercased() {
            case HelpCenter.linkScheme:
                onArticle(url.absoluteString.dropFirst(HelpCenter.linkScheme.count + 1).description)
            case HelpCenter.appLinkScheme:
                onAppLink(url.absoluteString.dropFirst(HelpCenter.appLinkScheme.count + 1).description)
            case "http", "https", "mailto":
                NSWorkspace.shared.open(url)
            default:
                // Links within the article (#section).
                if url.fragment != nil { return .allow }
            }
            return .cancel
        }
    }
}
