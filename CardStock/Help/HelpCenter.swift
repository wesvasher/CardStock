import Foundation

/// A Help Center section, in the order shown.
enum HelpCategory: String, CaseIterable, Sendable {
    case gettingStarted = "Getting Started"
    case writing = "Writing"
    case images = "Images"
    case theming = "Theming"
    case publishing = "Publishing"
    case questions = "Common Questions"
}

/// One help article, from a Markdown file in the app's `Help` folder.
///
/// Front matter: `title`, `category` (a `HelpCategory` name), `summary`
/// and `order` (position within the category). Links can point to other
/// articles with `help:<file name>` and to parts of the app with
/// `cardstock:<configuration|publishing|files|pages|home>`, or a Configuration
/// page by its `ConfigPage.linkName` (site-details, fonts, footer, …).
struct HelpArticle: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var category: HelpCategory
    var summary: String
    var order: Int
    var body: String

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return title.localizedCaseInsensitiveContains(q)
            || summary.localizedCaseInsensitiveContains(q)
            || body.localizedCaseInsensitiveContains(q)
    }
}

enum HelpCenter {
    static let linkScheme = "help"
    static let appLinkScheme = "cardstock"

    /// Every article bundled with the app, by category then order.
    static let articles: [HelpArticle] = {
        guard let folder = Bundle.main.url(forResource: "Help", withExtension: nil) else { return [] }
        return load(from: folder)
    }()

    static func article(_ id: String) -> HelpArticle? {
        articles.first { $0.id == id }
    }

    static func load(from folder: URL) -> [HelpArticle] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let articles = files.filter { $0.pathExtension == "md" }.compactMap { url -> HelpArticle? in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let (fm, body) = FrontMatter.parse(text)
            guard let title = fm.string("title"),
                  let category = fm.string("category").flatMap(HelpCategory.init(rawValue:))
            else { return nil }
            return HelpArticle(id: url.deletingPathExtension().lastPathComponent, title: title,
                               category: category, summary: fm.string("summary") ?? "",
                               order: fm.string("order").flatMap(Int.init) ?? 99, body: body)
        }
        let categoryOrder = HelpCategory.allCases
        return articles.sorted {
            let a = categoryOrder.firstIndex(of: $0.category)!, b = categoryOrder.firstIndex(of: $1.category)!
            return a != b ? a < b : ($0.order, $0.title) < ($1.order, $1.title)
        }
    }

    /// The article as a complete HTML page styled like macOS help.
    static func html(for article: HelpArticle) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="color-scheme" content="light dark">
        <title>\(escapeHTML(article.title))</title>
        <style>\(css)</style>
        </head>
        <body>
        <article>
        <p class="category">\(escapeHTML(article.category.rawValue))</p>
        <h1>\(escapeHTML(article.title))</h1>
        \(SiteRenderer.markdownToHTML(article.body))
        </article>
        </body>
        </html>
        """
    }

    private static let css = """
    :root{--bg:#fff;--text:#1d1d1f;--muted:#6e6e73;--accent:#0a66d8;--line:#e3e3e8;--soft:#f5f5f7;--tip:#eef5ff}
    @media (prefers-color-scheme:dark){:root{--bg:#1e1e1e;--text:#ececec;--muted:#a1a1a6;--accent:#4aa3ff;--line:#3a3a3c;--soft:#2a2a2c;--tip:#1d2a3a}}
    html{background:var(--bg)}
    body{margin:0;color:var(--text);font:15px/1.6 -apple-system,system-ui,sans-serif;-webkit-font-smoothing:antialiased}
    article{max-width:640px;margin:0 auto;padding:28px 28px 64px}
    .category{margin:0 0 4px;color:var(--muted);font-size:12px;font-weight:600;letter-spacing:.04em;text-transform:uppercase}
    h1{margin:0 0 18px;font-size:26px;line-height:1.2;letter-spacing:-.01em}
    h2{margin:30px 0 8px;font-size:18px}
    h3{margin:22px 0 6px;font-size:15px}
    p,ul,ol{margin:0 0 14px}
    li{margin:4px 0}
    ol{padding-left:0;list-style:none;counter-reset:step}
    ol>li{position:relative;padding-left:34px;counter-increment:step;margin:10px 0}
    ol>li::before{content:counter(step);position:absolute;left:0;top:1px;width:22px;height:22px;border-radius:50%;background:var(--accent);color:#fff;font-size:12px;font-weight:600;line-height:22px;text-align:center}
    a{color:var(--accent);text-decoration:none}
    a:hover{text-decoration:underline}
    code{font:13px ui-monospace,SFMono-Regular,Menlo,monospace;background:var(--soft);border:1px solid var(--line);border-radius:5px;padding:1px 5px}
    pre{background:var(--soft);border:1px solid var(--line);border-radius:8px;padding:12px 14px;overflow-x:auto}
    pre code{background:none;border:0;padding:0}
    blockquote{margin:16px 0;padding:10px 14px;background:var(--tip);border-left:3px solid var(--accent);border-radius:6px}
    blockquote p{margin:0}
    table{border-collapse:collapse;width:100%;margin:0 0 16px;font-size:14px}
    th,td{text-align:left;padding:7px 10px;border-bottom:1px solid var(--line);vertical-align:top}
    th{color:var(--muted);font-weight:600}
    hr{border:0;border-top:1px solid var(--line);margin:24px 0}
    strong{font-weight:600}
    """
}
