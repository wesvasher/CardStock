import AppKit
import SwiftUI

/// Signing in to GitHub with a personal access token: how to make one, and
/// a field to paste it into. Used on the Publishing page, in Settings when
/// adding an account, and when opening a site from GitHub.
struct GitHubSignInForm: View {
    @Environment(AppModel.self) private var model
    var intro: String
    /// Called with the account's login after a successful sign-in.
    var onSignedIn: ((String) -> Void)? = nil
    @State private var tokenText = ""

    static let tokenURL = URL(string: "https://github.com/settings/tokens/new?scopes=repo&description=CardStock")!

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(intro)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("1. Create a token on GitHub")
                    .font(.headline)
                Text("Make a classic personal access token with only the “repo” permission checked.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Open GitHub Token Page…") { NSWorkspace.shared.open(Self.tokenURL) }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("2. Paste your personal access token here")
                    .font(.headline)
                SecureField("Personal access token", text: $tokenText,
                            prompt: Text("Paste token (starts with ghp_)"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .onSubmit(signIn)
                Text("Saved in this Mac's Keychain, never in the site folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Sign In to GitHub", action: signIn)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(tokenText.trimmingCharacters(in: .whitespaces).isEmpty || model.isWorking)
        }
    }

    private func signIn() {
        let token = tokenText
        Task {
            if let login = await model.signIn(token: token) {
                tokenText = ""
                onSignedIn?(login)
            }
        }
    }
}
