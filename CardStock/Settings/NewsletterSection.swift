import SwiftUI

/// Configuration → Mailing List: the sign-up box that pages show where they
/// have a `<!-- newsletter -->` line. The form is embed code from a
/// newsletter service; CardStock adds a heading and text around it.
/// Saved in site.json (`newsletter`).
struct NewsletterSection: View {
    @Environment(AppModel.self) private var model
    @Binding var config: SiteConfig

    private var newsletter: Binding<SiteConfig.Newsletter> { $config.newsletter }

    /// Pages with a newsletter line.
    private var pages: [ContentItem] {
        (model.site?.items ?? []).filter { !$0.isLinkMenu && SiteConfig.Newsletter.isUsed(in: $0.body) }
    }

    var body: some View {
        Section {
            TextEditor(text: newsletter.embed)
                .font(.system(.callout, design: .monospaced))
                .frame(minHeight: 140)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                .overlay(alignment: .topLeading) {
                    if config.newsletter.embed.isEmpty {
                        Text("Paste embed code here, such as <iframe …></iframe> or a <form> and <script>")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .allowsHitTesting(false)
                    }
                }
        } header: {
            Text("Sign-Up Form")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                caption("Copy the embed code from your newsletter service, such as Buttondown, Kit, Mailchimp, beehiiv or Substack. Look for “Embed”, “Embedded form” or “Share” in its settings. CardStock uses the code as is.")
                caption("Some services' forms only work on your live site, not in the preview.")
            }
        }

        Section {
            TextField("Heading", text: newsletter.heading, prompt: Text("None"))
            TextField("Text", text: newsletter.text, prompt: Text("None"), axis: .vertical)
                .lineLimit(1...4)
            Picker("Style", selection: newsletter.style) {
                Text("Card").tag(SiteConfig.Newsletter.Style.card)
                Text("Plain").tag(SiteConfig.Newsletter.Style.plain)
            }
            .pickerStyle(.segmented)
            Picker("Alignment", selection: newsletter.alignment) {
                Text("Left").tag(SiteConfig.Newsletter.Alignment.left)
                Text("Center").tag(SiteConfig.Newsletter.Alignment.center)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Box")
        } footer: {
            caption("Shown above the form. Leave either empty if the embed code has its own. Card uses the card look from Components.")
        }

        Section {
            if pages.isEmpty {
                Text("Not in any pages yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(pages) { page in
                    LabeledContent(page.title) {
                        Button("Open") { model.selection = .item(page.id) }
                            .controlSize(.small)
                    }
                }
            }
        } header: {
            Text("Pages")
        } footer: {
            caption("To add the box to a page, open the page, click where it should go, and click the envelope button in the formatting bar. That adds a <!-- newsletter --> line, which the box replaces.")
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
