import SwiftUI

/// The color for "GitHub has updates this Mac doesn't": the sidebar seal
/// and the Publishing page banner share it.
extension Color {
    static let incomingUpdates = Color.purple
}

/// A purple seal with a number on it, for updates waiting on GitHub.
struct UpdateSeal: View {
    let count: Int
    var size: CGFloat = 20

    var body: some View {
        ZStack {
            Image(systemName: "seal.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.incomingUpdates.gradient)
            Text(count > 9 ? "9+" : "\(count)")
                .font(.system(size: size * (count > 9 ? 0.4 : 0.5), weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("\(count) \(count == 1 ? "update" : "updates") on GitHub")
    }
}

/// On the Publishing page when another Mac published changes this Mac
/// doesn't have: what came in, what it touches, and what to do about it.
struct IncomingUpdatesBanner: View {
    @Environment(AppModel.self) private var model
    let sync: SyncStatus
    @State private var confirmUseGitHub = false

    private var count: Int { sync.behind }
    private var overlap: [String] { sync.overlappingFiles }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                UpdateSeal(count: count, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(count) \(count == 1 ? "update" : "updates") published from another Mac")
                        .font(.title3.bold())
                    Text("GitHub has changes that aren't on this Mac yet. Get them before you edit, so both Macs stay in step.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !sync.incoming.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Published")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(Array(sync.incoming.enumerated()), id: \.offset) { _, snapshot in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(Color.incomingUpdates)
                            Text(snapshot.message)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            if let date = snapshot.date {
                                Text(date, format: .relative(presentation: .named))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if count > sync.incoming.count {
                        Text("and \(count - sync.incoming.count) earlier")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !sync.incomingFiles.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Changes")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(describe(sync.incomingFiles))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            nextStep
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.incomingUpdates.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.incomingUpdates.opacity(0.35)))
        .confirmationDialog("Use GitHub's version of \(names(overlap))?", isPresented: $confirmUseGitHub) {
            Button("Use GitHub's Version") {
                let paths = overlap
                Task { await model.useGitHubVersion(of: paths) }
            }
        } message: {
            Text("Your edits to \(overlap.count == 1 ? "it" : "them") on this Mac are replaced. A copy of each goes to the Trash first, named “(edits from this Mac)”, so you can redo them after getting the latest.")
        }
    }

    // MARK: - What to do

    @ViewBuilder
    private var nextStep: some View {
        let local = sync.changedFiles.count
        VStack(alignment: .leading, spacing: 10) {
            Text("What to do")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if !overlap.isEmpty {
                Label {
                    Text("Both Macs changed \(names(overlap)). CardStock can't combine edits to the same file, so publishing would stop without changing anything. Use GitHub's version here, then get the latest and redo your edits.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                Button {
                    confirmUseGitHub = true
                } label: {
                    Label("Use GitHub's Version…", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.incomingUpdates)
                .controlSize(.large)
                .disabled(model.isWorking)
            } else if sync.hasLocalChanges {
                Text("You also have \(local == 0 ? "changes" : "\(local) changed \(local == 1 ? "file" : "files")") on this Mac. They don't touch the same files, so they combine cleanly: click **Flatten and Push to GitHub** below and CardStock brings in the updates first, then publishes yours.")
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Nothing on this Mac is waiting to publish, so this is safe: click **Get Latest from GitHub** below to download the updates and refresh the site here.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Describing files

    /// "Hello World", "About" and 2 images.
    private func describe(_ paths: [String]) -> String {
        var named: [String] = []
        var images = 0, other = 0, newItems = 0
        var theme = false, details = false
        for path in paths {
            if let title = title(for: path) {
                named.append("“\(title)”")
            } else if path == Site.configFile {
                details = true
            } else if path.hasPrefix("theme/") {
                theme = true
            } else if path.hasSuffix(".md") && ["posts/", "pages/", "projects/"].contains(where: path.hasPrefix) {
                // Added (or removed) on the other Mac, so there's no title here.
                newItems += 1
            } else if path.hasPrefix("media/") {
                images += 1
            } else {
                other += 1
            }
        }
        var parts = Array(named.prefix(6))
        if named.count > 6 { parts.append("\(named.count - 6) more \(named.count - 6 == 1 ? "page" : "pages")") }
        if newItems > 0 { parts.append("\(newItems) \(newItems == 1 ? "post or page" : "posts or pages") added or removed") }
        if details { parts.append("Configuration") }
        if theme { parts.append("the theme") }
        if images > 0 { parts.append("\(images) \(images == 1 ? "file" : "files") in media") }
        if other > 0 { parts.append("\(other) other \(other == 1 ? "file" : "files")") }
        return ListFormatter.localizedString(byJoining: parts)
    }

    private func names(_ paths: [String]) -> String {
        ListFormatter.localizedString(byJoining: paths.map { title(for: $0).map { "“\($0)”" } ?? $0 })
    }

    /// The title of the post, page or project stored at a site-relative path.
    private func title(for path: String) -> String? {
        guard let site = model.site else { return nil }
        let full = site.root.appending(path: path).standardizedFileURL.path
        return site.items.first { $0.fileURL.standardizedFileURL.path == full }?.title
    }
}
