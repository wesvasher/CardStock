import AppKit
import SwiftUI

/// The website's high-level details: title, description, address, language
/// and storage. Configuration → Site Details.
struct SiteDetailsView: View {
    @Environment(AppModel.self) private var model
    let site: Site

    var body: some View {
        Form {
            Section("Site") {
                TextField("Title", text: config(\.title))
                TextField("Description", text: config(\.description), axis: .vertical)
                    .lineLimit(1...4)
                TextField("Author", text: config(\.author))
                TextField("Web address", text: config(\.url), prompt: Text("https://example.pages.dev"))
                TextField("Language", text: config(\.language), prompt: Text("en"))
            }

            SiteIconSection()

            StorageSection()
        }
        .formStyle(.grouped)
        .onAppear { model.refreshStorage() }
    }

    private func config<T>(_ keyPath: WritableKeyPath<SiteConfig, T>) -> Binding<T> {
        Binding(
            get: { (model.site?.config ?? site.config)[keyPath: keyPath] },
            set: { newValue in
                guard var config = model.site?.config else { return }
                config[keyPath: keyPath] = newValue
                model.updateConfig(config)
            })
    }
}

/// How big the site is, compared with GitHub's and Cloudflare's limits.
private struct StorageSection: View {
    @Environment(AppModel.self) private var model

    private func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var body: some View {
        Section {
            if let storage = model.storage {
                repositoryRow(storage)

                if let git = storage.gitBytes {
                    LabeledContent("History on this Mac (.git)") { Text(size(git)).monospacedDigit() }
                        .help("Every saved version of your site. GitHub stores roughly the same thing.")
                }
                LabeledContent("Media files") { Text(size(storage.mediaBytes)).monospacedDigit() }
                LabeledContent("Built website (public)") {
                    Text("\(size(storage.publicBytes)) · \(storage.publicFileCount.formatted()) of \(SiteStorage.cloudflareMaxFiles.formatted()) files")
                        .monospacedDigit()
                }
                .help("Cloudflare Pages' free plan allows up to \(SiteStorage.cloudflareMaxFiles.formatted()) files per site.")

                ForEach(storage.largeFiles) { file in
                    largeFileRow(file)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Measuring…").foregroundStyle(.secondary)
                }
            }

            DisclosureGroup("About GitHub and Cloudflare limits") {
                VStack(alignment: .leading, spacing: 8) {
                    limit("GitHub doesn't charge for public or private repositories, and has no fixed storage limit for them. It asks that repositories stay small, ideally under about 1 GB.")
                    limit("GitHub warns about any single file over 50 MB and refuses files over 100 MB.")
                    limit("Cloudflare Pages won't serve a file over 25 MB, and the free plan allows up to 20,000 files per site.")
                    limit("Deleting a file doesn't shrink your history: GitHub keeps every version ever published. Optimized images keep it small.")
                    limit("Images appear in both media and public, but git stores identical files once, so they don't count twice.")
                    Link("GitHub's guidance on repository size",
                         destination: URL(string: "https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github")!)
                        .font(.caption)
                    Link("Cloudflare Pages limits",
                         destination: URL(string: "https://developers.cloudflare.com/pages/platform/limits/")!)
                        .font(.caption)
                }
                .padding(.vertical, 4)
            }
        } header: {
            HStack {
                Text("Storage")
                Spacer()
                Button {
                    model.refreshStorage()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(model.isMeasuringStorage)
                .help("Measure again")
            }
        }
    }

    /// The headline number: GitHub's figure when linked, otherwise this
    /// Mac's history, against the ~1 GB guideline.
    @ViewBuilder
    private func repositoryRow(_ storage: SiteStorage) -> some View {
        let linked = model.project.github != nil
        let bytes = model.githubRepoBytes ?? storage.gitBytes
        if let bytes {
            let limit = SiteStorage.githubRecommendedRepoBytes
            let fraction = min(Double(bytes) / Double(limit), 1)
            let color: Color = fraction < 0.5 ? .green : fraction < 0.9 ? .orange : .red
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.githubRepoBytes != nil ? "Repository on GitHub" : "Repository")
                    Spacer()
                    Text("\(size(bytes)) of about \(size(limit))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: max(fraction, 0.005))
                    .tint(color)
                Text(caption(linked: linked, fraction: fraction))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
        } else {
            Text("This site isn't linked to GitHub, so it has no repository yet. The sizes below are what it would start with.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func caption(linked: Bool, fraction: Double) -> String {
        var text: String
        if model.githubRepoBytes != nil {
            text = "As reported by GitHub, which updates this number from time to time, so it can lag behind your last publish."
        } else if linked {
            text = "Measured from the history on this Mac. Sign in to GitHub to see GitHub's own figure."
        } else {
            text = "Measured from the history on this Mac."
        }
        if fraction >= 0.9 {
            text += " You're near GitHub's suggested size. Consider removing large files you don't need."
        } else if fraction >= 0.5 {
            text += " Over half of GitHub's suggested size."
        }
        return text
    }

    private func largeFileRow(_ file: SiteStorage.LargeFile) -> some View {
        let problem: String
        let color: Color
        if file.bytes > SiteStorage.githubMaxFileBytes {
            problem = "Too big for GitHub (over 100 MB). Publishing will fail until it's removed or made smaller."
            color = .red
        } else if file.bytes > SiteStorage.githubWarnFileBytes {
            problem = "Over 50 MB: GitHub will warn, and Cloudflare won't serve files over 25 MB."
            color = .orange
        } else {
            problem = "Over 25 MB: Cloudflare Pages won't serve it on your live site."
            color = .orange
        }
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(file.path) · \(size(file.bytes))")
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Show in Finder") {
                if let root = model.site?.root {
                    NSWorkspace.shared.activateFileViewerSelecting([root.appending(path: file.path)])
                }
            }
            .controlSize(.small)
        }
    }

    private func limit(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("•").foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
