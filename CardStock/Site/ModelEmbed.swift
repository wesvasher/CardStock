import Foundation

/// 3D models in a page's Markdown: a line of its own like
/// `<!-- model /media/files/chair.glb "A walnut chair" -->` shows the model
/// in Google's `<model-viewer>`, which visitors can drag to turn and pinch
/// or scroll to zoom, with a button to see it in their room on phones and
/// tablets (AR). The viewer's script is bundled with CardStock and copied
/// into sites that use it, so pages don't load it from anyone's server.
/// Lines in code blocks are left alone.
enum ModelEmbed {
    /// Where the viewer's script is published and previewed.
    static let scriptPath = "/assets/cardstock/model-viewer.min.js"
    /// glTF: `.glb` (one file, the best choice) or `.gltf`.
    static let extensions: Set<String> = ["glb", "gltf"]

    static func isModelFile(_ path: String) -> Bool {
        let clean = path.split(separator: "?").first.map(String.init) ?? path
        return extensions.contains((clean as NSString).pathExtension.lowercased())
    }

    /// How a model shows: its size, background and spin. Written after
    /// the description as `width=60% height=400 background=transparent
    /// spin=off`; settings left at their defaults aren't written.
    struct Options: Equatable, Sendable {
        enum Background: Equatable, Sendable {
            /// The theme's card color (Colors → Surface).
            case theme
            /// None: the page shows through.
            case transparent
            /// A color as `#rrggbb`.
            case color(String)
        }

        static let widths = 10...100
        static let heights = 100...1200

        /// Percent of the page's text width, centered (phones always get
        /// the full width).
        var width = 100
        /// Pixels; nil is 4:3 at whatever width it has.
        var height: Int?
        var background = Background.theme
        /// Turns slowly until touched.
        var spin = true

        init() {}

        /// The words written in the line for settings that aren't defaults.
        var tokens: [String] {
            var t: [String] = []
            if width != 100 { t.append("width=\(width)%") }
            if let height { t.append("height=\(height)") }
            switch background {
            case .theme: break
            case .transparent: t.append("background=transparent")
            case .color(let hex): t.append("background=\(hex)")
            }
            if !spin { t.append("spin=off") }
            return t
        }

        /// Reads `key=value` words; unknown or unsafe values are left out.
        init(tokens: [String]) {
            for token in tokens {
                let parts = token.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                let value = parts[1].lowercased()
                switch parts[0].lowercased() {
                case "width":
                    if let n = Int(value.hasSuffix("%") ? String(value.dropLast()) : value) {
                        width = min(max(n, Self.widths.lowerBound), Self.widths.upperBound)
                    }
                case "height":
                    if let n = Int(value.hasSuffix("px") ? String(value.dropLast(2)) : value) {
                        height = min(max(n, Self.heights.lowerBound), Self.heights.upperBound)
                    }
                case "background":
                    if value == "transparent" || value == "none" { background = .transparent }
                    else if let hex = Self.hexColor(value) { background = .color(hex) }
                case "spin":
                    spin = !["off", "no", "false"].contains(value)
                default:
                    break
                }
            }
        }

        /// `#abc`, `#aabbcc` or `#aabbccdd` as written, lowercased; nil
        /// for anything else, so nothing but a color reaches the CSS.
        static func hexColor(_ s: String) -> String? {
            let digits = s.hasPrefix("#") ? String(s.dropFirst()) : s
            guard [3, 6, 8].contains(digits.count), digits.allSatisfy(\.isHexDigit) else { return nil }
            return "#" + digits.lowercased()
        }
    }

    /// The line for a model. Quotes and `--` can't be in the description,
    /// since they'd end it (or the comment) early.
    static func marker(src: String, alt: String, options: Options = Options()) -> String {
        let text = BuyButton.cleanLabel(alt)
        let parts = ["model", src] + (text.isEmpty ? [] : ["\"\(text)\""]) + options.tokens
        return "<!-- " + parts.joined(separator: " ") + " -->"
    }

    private static let pattern = try! NSRegularExpression(
        pattern: #"^<!--\s*model\s+([^\s"]+?)(?:\s+"([^"]*)")?((?:\s+[A-Za-z]+=[^\s"]+?)*)\s*-->$"#, options: .caseInsensitive)

    /// The model's address, description and settings in a model line, if
    /// it is one. The address is a site path (`/media/…`) or an https link
    /// to a `.glb` or `.gltf` file.
    static func parse(_ line: String) -> (src: String, alt: String, options: Options)? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.lowercased().hasPrefix("<!--"),
              let match = pattern.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
              let srcRange = Range(match.range(at: 1), in: t) else { return nil }
        let src = String(t[srcRange])
        guard isModelFile(src), src.hasPrefix("/") && !src.hasPrefix("//") || src.lowercased().hasPrefix("https://") else { return nil }
        let alt = Range(match.range(at: 2), in: t).map { String(t[$0]).trimmingCharacters(in: .whitespaces) } ?? ""
        let tokens = Range(match.range(at: 3), in: t).map { t[$0].split(whereSeparator: \.isWhitespace).map(String.init) } ?? []
        return (src, alt.isEmpty ? "3D model" : alt, Options(tokens: tokens))
    }

    /// Turns every model line outside code blocks into the viewer.
    static func markPlaces(in markdown: String) -> String {
        guard markdown.range(of: "model", options: .caseInsensitive) != nil, markdown.contains("<!--") else { return markdown }
        return PageWidget.eachLine(of: markdown) { line in
            // Blank lines around it keep it a block of its own.
            parse(line).map { "\n" + html(src: $0.src, alt: $0.alt, options: $0.options) + "\n" }
        }
    }

    /// True when the Markdown has a model line outside code blocks.
    static func isUsed(in markdown: String) -> Bool {
        var found = false
        PageWidget.eachLine(of: markdown) { line in
            if parse(line) != nil { found = true }
            return nil
        }
        return found
    }

    /// The viewer: turn by dragging, zoom, a slow spin until touched, a soft
    /// shadow, and AR on phones and tablets (iPhone and iPad get a USDZ
    /// made from the model as they open it).
    static func html(src: String, alt: String, options: Options = Options()) -> String {
        var box: [String] = []
        if options.width < 100 { box.append("max-width: \(options.width)%") }
        var viewer: [String] = []
        if let height = options.height { viewer += ["height: \(height)px", "aspect-ratio: auto"] }
        switch options.background {
        case .theme: break
        case .transparent: viewer.append("background: transparent")
        case .color(let hex): viewer.append("background: \(hex)")
        }
        let style = { (rules: [String]) in rules.isEmpty ? "" : #" style="\#(rules.joined(separator: "; "))""# }
        let spin = options.spin ? #" auto-rotate auto-rotate-delay="1500""# : ""
        return #"<div class="model-embed"\#(style(box))><model-viewer src="\#(escapeHTML(src))" alt="\#(escapeHTML(alt))"\#(style(viewer)) camera-controls touch-action="pan-y"\#(spin) shadow-intensity="1" ar ar-modes="webxr scene-viewer quick-look" loading="lazy"></model-viewer></div>"#
    }

    /// True when a page's HTML shows a model, so it needs the script.
    static func isShown(in html: String) -> Bool { html.contains("<model-viewer") }

    /// The script and styles for pages with a model, for the `<head>`.
    static let headHTML = """
    <script type="module" src="\(scriptPath)"></script>
    <style>
    .model-embed { margin: 1.5rem auto; }
    @media (max-width: 600px) { .model-embed { max-width: none !important; } }
    .model-embed model-viewer { display: block; width: 100%; aspect-ratio: 4 / 3; max-height: 80vh; background: var(--card); border-radius: var(--image-radius, 0); --poster-color: transparent; }
    </style>
    """

    /// The bundled script, from the app.
    static var bundledScript: URL? {
        Bundle.main.url(forResource: "ModelViewer", withExtension: nil)?.appending(path: "model-viewer.min.js")
    }
}
