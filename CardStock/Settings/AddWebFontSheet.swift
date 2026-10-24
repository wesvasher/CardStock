import SwiftUI

/// Asks for a web font link, looks it up, and adds its fonts to the site.
struct AddWebFontSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var link = ""
    @State private var isAdding = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add a Web Font")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Paste the web font link")
                    .font(.callout.weight(.medium))
                TextField("Web font link", text: $link,
                          prompt: Text("https://fonts.googleapis.com/css2?family=…"), axis: .vertical)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .focused($focused)
                    .disabled(isAdding)
                Text("A stylesheet link from Google Fonts, Adobe Fonts or Bunny Fonts (the whole <link> tag works too), or a direct link to a .woff2, .woff, .ttf or .otf file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if isAdding {
                    ProgressView().controlSize(.small)
                    Text("Looking up the font…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Font", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAdding)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { focused = true }
    }

    private func add() {
        error = nil
        isAdding = true
        Task {
            defer { isAdding = false }
            do {
                let added = try await model.addWebFont(link: link)
                dismiss()
                model.showToast(Self.message(for: added.map(\.family)))
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    nonisolated static func message(for names: [String]) -> String {
        let quoted = names.map { "“\($0)”" }
        let list: String
        switch quoted.count {
        case 0: list = "The font"
        case 1: list = quoted[0]
        case 2: list = "\(quoted[0]) and \(quoted[1])"
        default: list = quoted.dropLast().joined(separator: ", ") + " and " + quoted.last!
        }
        return "\(list) added to the font menus."
    }
}

/// A short message that slides up from the bottom of the window.
struct ToastView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.callout.weight(.medium))
            .symbolRenderingMode(.multicolor)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.separator))
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
    }
}
