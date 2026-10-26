import AppKit
import SwiftUI

/// How big the site is, compared with GitHub's and Cloudflare's limits.
struct StorageCard: View {
    @Environment(AppModel.self) private var model

    private func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var body: some View {
        DashboardCard(title: "Storage", subtitle: "How big your site is, compared with GitHub's and Cloudflare's limits.") {
            if let storage = model.storage {
                repositoryRow(storage)
                VStack(spacing: 8) {
                    if let git = storage.gitBytes {
                        row("History on this Mac (.git)", size(git))
                            .help("Every saved version of your site. GitHub stores roughly the same thing.")
                    }
                    row("Media files", size(storage.mediaBytes))
                    row("Built website (public)",
                        "\(size(storage.publicBytes)) · \(storage.publicFileCount.formatted()) of \(SiteStorage.cloudflareMaxFiles.formatted()) files")
                        .help("Cloudflare Pages' free plan allows up to \(SiteStorage.cloudflareMaxFiles.formatted()) files per site.")
                }
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                model.refreshStorage()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(model.isMeasuringStorage)
            .help("Measure again")
            .padding(18)
        }
        .onAppear { model.refreshStorage() }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.callout)
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
