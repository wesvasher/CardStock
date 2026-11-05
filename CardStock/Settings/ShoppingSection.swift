import AppKit
import SwiftUI

/// Configuration → Shopping: picks how the site sells things. For now the
/// only checkout service is Stripe Payment Links; choosing it adds the cart
/// button to the editor's formatting bar and Payment link fields to Page
/// Settings. Saved in site.json (`shopping`).
struct ShoppingSection: View {
    @Environment(AppModel.self) private var model
    @Binding var config: SiteConfig

    private var shopping: Binding<SiteConfig.Shopping> { $config.shopping }

    /// Pages with a Buy button: a button line in the text, or a Payment
    /// link in Page Settings (shop items count when they have a Buy link).
    private var pages: [ContentItem] {
        (model.site?.items ?? []).filter { page in
            guard !page.isLinkMenu else { return false }
            let link = (page.frontMatter.string("buy") ?? "").trimmingCharacters(in: .whitespaces)
            return BuyButton.isUsed(in: page.body) || BuyButton.isWebLink(link)
        }
    }

    var body: some View {
        Section {
            ForEach(SiteConfig.Shopping.Provider.allCases, id: \.self) { provider in
                ProviderRow(provider: provider, isSelected: config.shopping.provider == provider) {
                    withAnimation(.snappy(duration: 0.2)) { config.shopping.provider = provider }
                }
            }
        } header: {
            Text("Checkout Service")
        } footer: {
            caption("How visitors pay. CardStock never sees payments or card details: the service runs checkout and sends you the money. More services, such as shopping carts, may come later.")
        }

        if config.shopping.usesPaymentLinks {
            Section {
                step(1, "In your Stripe Dashboard, open Payment Links and click New. Choose a product and price (or add one), and set what happens after payment.")
                step(2, "Click Create link, then copy the link. It starts with https://buy.stripe.com/.")
                step(3, "In CardStock, open a page and click the cart button in the formatting bar where the button should go, then paste the link. Or paste it in Payment link in the page's Page Settings to show the button after the page's text.")
                HStack {
                    Button("Open Stripe Payment Links") {
                        if let url = URL(string: "https://dashboard.stripe.com/payment-links") { NSWorkspace.shared.open(url) }
                    }
                    Spacer()
                }
            } header: {
                Text("Set Up Stripe Payment Links")
            } footer: {
                caption("A Stripe account is free to make; Stripe takes a fee from each sale. Payment Links work without a shopping cart: each button buys one product, and Stripe's page can let buyers choose how many.")
            }

            Section {
                TextField("Button text", text: shopping.buttonLabel, prompt: Text("Buy Now"))
            } header: {
                Text("Buy Buttons")
            } footer: {
                caption("What new Buy buttons say. You can change the text of each button when you add it. Buttons use the button style from Components and open checkout in a new tab.")
            }

            Section {
                if pages.isEmpty {
                    Text("No pages have a Buy button yet.")
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
            }
        } else if !pages.isEmpty {
            Section {
                caption("\(pages.count) \(pages.count == 1 ? "page has" : "pages have") a Buy button. Buttons typed into a page's text still show; Payment links in Page Settings are hidden until you choose Stripe Payment Links again. Shop items' Buy links always show.")
            }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.15), in: Circle())
                .foregroundStyle(.tint)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// One checkout service to choose: icon, name and what it does, with a
/// checkmark on the chosen one.
private struct ProviderRow: View {
    let provider: SiteConfig.Shopping.Provider
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: provider.systemImage)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.title).font(.body.weight(.medium))
                    Text(provider.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
