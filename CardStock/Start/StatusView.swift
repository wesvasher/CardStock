import SwiftUI

/// Status, under Start in the sidebar: how the site gets from this Mac to
/// the web (and which steps are set up), the health checklist and activity
/// log side by side, how big it is against GitHub's and Cloudflare's limits,
/// and help articles for fixing problems.
struct StatusView: View {
    @Environment(AppModel.self) private var model
    let site: Site

    private var current: Site { model.site ?? site }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HowItWorksCard()
                // Side by side at one height; each scrolls inside.
                HStack(alignment: .top, spacing: 16) {
                    HealthCard(site: current)
                    ActivityLogCard()
                }
                .frame(height: 520)
                StorageCard()
                FixProblemsCard()
            }
            .padding(28)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .onAppear { model.refreshFiles() }
    }
}

/// Help articles about publishing and connection problems.
private struct FixProblemsCard: View {
    @Environment(AppModel.self) private var model

    private let articles: [(id: String, title: String, detail: String, icon: String)] = [
        ("troubleshooting", "When something goes wrong", "Fixes for publishing and preview problems.", "wrench.and.screwdriver"),
        ("connect-github", "Connect to GitHub", "Step by step, from token to linked site.", "arrow.triangle.branch"),
        ("cloudflare", "Host on Cloudflare Pages", "Put your site online and add your own domain.", "cloud"),
        ("another-mac", "Work on another Mac", "Edit the same site from more than one computer.", "desktopcomputer"),
        ("without-github", "Use CardStock without GitHub", "Build the HTML yourself and upload it anywhere.", "externaldrive"),
    ]

    var body: some View {
        DashboardCard(title: "Fix a Problem", subtitle: "Guides from the Help Center.") {
            VStack(spacing: 6) {
                ForEach(articles, id: \.id) { article in
                    Button { model.showHelp(article.id) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: article.icon)
                                .foregroundStyle(.tint)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(article.title).font(.callout.weight(.medium))
                                Text(article.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
