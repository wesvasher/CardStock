import Testing
@testable import CardStock

struct VideoEmbedTests {
    let youTubeCode = #"<iframe width="560" height="315" src="https://www.youtube.com/embed/ZIteqB0Rkoo?si=lXKqs9mgQFnkwlGF" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>"#

    @Test func embedCodeBecomesThePlayer() {
        let html = SiteRenderer.markdownToHTML("Watch this:\n\n\(youTubeCode)\n\nThanks!")
        #expect(html.contains(#"<div class="video-embed"><iframe src="https://www.youtube-nocookie.com/embed/ZIteqB0Rkoo""#))
        #expect(!html.contains("width=\"560\""))
        #expect(!html.contains("si=lXKq"))
        #expect(html.contains("<p>Thanks!</p>"))
    }

    @Test func linksOnTheirOwnLine() {
        let html = SiteRenderer.markdownToHTML("Intro\nhttps://youtu.be/ZIteqB0Rkoo?t=1m30s\n\n<https://vimeo.com/76979871>")
        #expect(html.contains("youtube-nocookie.com/embed/ZIteqB0Rkoo?start=90"))
        #expect(html.contains("player.vimeo.com/video/76979871"))
        #expect(html.contains("<p>Intro</p>"))
        // A link in a sentence, a code block and other iframes stay as they are.
        let kept = SiteRenderer.markdownToHTML("See https://youtu.be/ZIteqB0Rkoo here.\n\n```\nhttps://youtu.be/ZIteqB0Rkoo\n```\n\n<iframe src=\"https://open.spotify.com/embed/x\"></iframe>")
        #expect(!kept.contains("video-embed"))
        #expect(kept.contains("open.spotify.com/embed/x"))
    }

    @Test func startTimes() {
        #expect(SiteRenderer.youTubeStart("https://youtu.be/x?t=90") == 90)
        #expect(SiteRenderer.youTubeStart("https://youtu.be/x?t=1h2m3s") == 3723)
        #expect(SiteRenderer.youTubeStart("https://www.youtube.com/embed/x?start=15") == 15)
        #expect(SiteRenderer.youTubeStart("https://www.youtube.com/watch?v=x") == nil)
    }

    @Test func previewShowsThumbnails() {
        let page = SiteRenderer.markdownToHTML("https://www.youtube.com/watch?v=ZIteqB0Rkoo&t=90\n\nhttps://vimeo.com/76979871")
        let preview = VideoEmbed.previewPlaceholders(in: page)
        #expect(preview.contains(#"href="https://www.youtube.com/watch?v=ZIteqB0Rkoo&t=90s""#))
        #expect(preview.contains("i.ytimg.com/vi/ZIteqB0Rkoo/hqdefault.jpg"))
        #expect(!preview.contains("youtube-nocookie"))
        #expect(preview.contains("player.vimeo.com/video/76979871"))
        // Raw embed code too, and nothing else changes.
        #expect(VideoEmbed.previewPlaceholders(in: "<div>" + youTubeCode + "</div>").hasPrefix("<div><a href="))
        #expect(VideoEmbed.previewPlaceholders(in: "<p>youtube</p>") == "<p>youtube</p>")
    }
}
