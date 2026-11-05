import SwiftUI

/// Adds a Buy button at the cursor: a Stripe Payment Link and the button's
/// text. Inserts a `<!-- buy … -->` line, which the page shows as a button.
struct InsertBuyButtonSheet: View {
    @Environment(\.dismiss) private var dismiss
    let defaultLabel: String
    let insert: (_ link: String, _ label: String) -> Void

    @State private var link = ""
    @State private var label = ""

    private var trimmedLink: String { link.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isValid: Bool { BuyButton.isWebLink(trimmedLink) }

    private var note: String {
        if trimmedLink.isEmpty { return "In Stripe, open Payment Links, copy a product's link, and paste it here." }
        if !isValid { return "Paste the whole link, starting with https://." }
        if !BuyButton.isStripeLink(trimmedLink) { return "This isn't a Stripe Payment Link (they start with https://buy.stripe.com/), but any checkout link works." }
        return "Clicking the button opens Stripe's checkout page in a new tab."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Add a Buy Button", systemImage: "cart.badge.plus")
                .font(.title3.bold())
            Form {
                TextField("Payment link", text: $link, prompt: Text("https://buy.stripe.com/…"))
                TextField("Button text", text: $label, prompt: Text(defaultLabel))
            }
            .formStyle(.columns)
            Text(note)
                .font(.callout)
                .foregroundStyle(isValid || trimmedLink.isEmpty ? Color.secondary : Color.orange)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Button") {
                    let text = label.trimmingCharacters(in: .whitespaces)
                    insert(trimmedLink, text.isEmpty ? defaultLabel : text)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
