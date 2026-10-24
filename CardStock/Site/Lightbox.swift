import Foundation

/// A small, theme-independent lightbox added to pages that have linked
/// images (`[![small](small.jpg)](large.jpg)`). Clicking one opens the large
/// version; arrow keys, buttons or swipes move through every linked image
/// on the page; Escape or clicking the backdrop closes it.
enum Lightbox {
    /// True when the page has an image wrapped in a link to an image file.
    static func isNeeded(in html: String) -> Bool {
        html.range(of: #"<a\s+href="[^"]+\.(?:jpe?g|png|gif|webp|avif|svg)"[^>]*>\s*<img"#,
                   options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Adds the lightbox's CSS to `<head>` and its script before `</body>`.
    static func inject(into html: String) -> String {
        guard isNeeded(in: html) else { return html }
        var result = html
        if let head = result.range(of: "</head>", options: .caseInsensitive) {
            result.insert(contentsOf: "<style id=\"cardstock-lightbox\">\n\(css)</style>\n", at: head.lowerBound)
        }
        let script = "<script id=\"cardstock-lightbox-script\">\n\(js)</script>\n"
        if let body = result.range(of: "</body>", options: [.caseInsensitive, .backwards]) {
            result.insert(contentsOf: script, at: body.lowerBound)
        } else {
            result += script
        }
        return result
    }

    static let css = """
    .cs-lightbox{position:fixed;inset:0;z-index:9999;display:flex;align-items:center;justify-content:center;background:rgba(0,0,0,.9);opacity:0;visibility:hidden;transition:opacity .2s ease,visibility .2s ease}
    .cs-lightbox.cs-open{opacity:1;visibility:visible}
    .cs-lightbox figure{margin:0;display:flex;flex-direction:column;align-items:center;gap:.75rem;max-width:92vw}
    .cs-lightbox img{max-width:92vw;max-height:82vh;object-fit:contain;border-radius:4px;box-shadow:0 12px 48px rgba(0,0,0,.5);transition:opacity .15s ease}
    .cs-lightbox img.cs-loading{opacity:.4}
    .cs-lightbox figcaption{color:#e5e5e5;font:14px/1.4 -apple-system,system-ui,sans-serif;text-align:center;max-width:70ch}
    .cs-lightbox button{position:absolute;display:flex;align-items:center;justify-content:center;width:44px;height:44px;border:0;border-radius:999px;background:rgba(255,255,255,.14);color:#fff;font:28px/1 -apple-system,system-ui,sans-serif;cursor:pointer}
    .cs-lightbox button:hover,.cs-lightbox button:focus-visible{background:rgba(255,255,255,.28);outline:none}
    .cs-lb-close{top:16px;right:16px}
    .cs-lb-prev{left:16px;top:50%;transform:translateY(-50%)}
    .cs-lb-next{right:16px;top:50%;transform:translateY(-50%)}
    .cs-lightbox.cs-single .cs-lb-prev,.cs-lightbox.cs-single .cs-lb-next{display:none}
    .cs-lb-count{position:absolute;bottom:18px;left:50%;transform:translateX(-50%);color:#bbb;font:13px -apple-system,system-ui,sans-serif}
    html.cs-lb-lock{overflow:hidden}
    a>img{cursor:zoom-in}
    @media (max-width:600px){.cs-lb-prev,.cs-lb-next{display:none!important}}
    @media (prefers-reduced-motion:reduce){.cs-lightbox,.cs-lightbox img{transition:none}}

    """

    static let js = """
    (function () {
      var imageLink = /\\.(jpe?g|png|gif|webp|avif|svg)([?#].*)?$/i;
      var links = Array.prototype.filter.call(document.querySelectorAll("a[href]"), function (a) {
        return a.querySelector("img") && imageLink.test(a.getAttribute("href"));
      });
      if (!links.length) return;
      var box, img, caption, count, index = 0;

      function build() {
        box = document.createElement("div");
        box.className = "cs-lightbox";
        box.setAttribute("role", "dialog");
        box.setAttribute("aria-modal", "true");
        box.setAttribute("aria-label", "Image viewer");
        box.innerHTML = '<button class="cs-lb-close" aria-label="Close">&times;</button>' +
          '<button class="cs-lb-prev" aria-label="Previous image">&lsaquo;</button>' +
          '<figure><img alt=""><figcaption></figcaption></figure>' +
          '<button class="cs-lb-next" aria-label="Next image">&rsaquo;</button>' +
          '<div class="cs-lb-count" aria-live="polite"></div>';
        document.body.appendChild(box);
        img = box.querySelector("img");
        caption = box.querySelector("figcaption");
        count = box.querySelector(".cs-lb-count");
        img.addEventListener("load", function () { img.classList.remove("cs-loading"); });
        box.addEventListener("click", function (e) {
          if (e.target === box || e.target.tagName === "FIGURE") close();
        });
        box.querySelector(".cs-lb-close").addEventListener("click", close);
        box.querySelector(".cs-lb-prev").addEventListener("click", function (e) { e.stopPropagation(); show(index - 1); });
        box.querySelector(".cs-lb-next").addEventListener("click", function (e) { e.stopPropagation(); show(index + 1); });
        var startX = null;
        box.addEventListener("touchstart", function (e) { startX = e.touches[0].clientX; }, { passive: true });
        box.addEventListener("touchend", function (e) {
          if (startX === null) return;
          var dx = e.changedTouches[0].clientX - startX;
          if (Math.abs(dx) > 50) show(index + (dx < 0 ? 1 : -1));
          startX = null;
        });
      }

      function show(n) {
        index = (n + links.length) % links.length;
        var link = links[index], thumb = link.querySelector("img");
        img.classList.add("cs-loading");
        img.src = link.href;
        img.alt = thumb.alt || "";
        caption.textContent = thumb.alt || "";
        caption.hidden = !thumb.alt;
        count.textContent = links.length > 1 ? (index + 1) + " / " + links.length : "";
        box.classList.toggle("cs-single", links.length < 2);
        [index + 1, index - 1].forEach(function (k) {
          new Image().src = links[(k + links.length) % links.length].href;
        });
      }

      function open(n) {
        if (!box) build();
        show(n);
        box.classList.add("cs-open");
        document.documentElement.classList.add("cs-lb-lock");
        box.querySelector(".cs-lb-close").focus();
      }

      function close() {
        box.classList.remove("cs-open");
        document.documentElement.classList.remove("cs-lb-lock");
        links[index].focus();
      }

      links.forEach(function (link, n) {
        link.addEventListener("click", function (e) {
          if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
          e.preventDefault();
          open(n);
        });
      });

      document.addEventListener("keydown", function (e) {
        if (!box || !box.classList.contains("cs-open")) return;
        if (e.key === "Escape") close();
        else if (e.key === "ArrowRight") show(index + 1);
        else if (e.key === "ArrowLeft") show(index - 1);
      });
    })();

    """
}
