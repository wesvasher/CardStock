import SwiftUI

/// A full-width card on the Start screen showing how a CardStock site travels: written on
/// this Mac, kept on GitHub (so any Mac with CardStock can work on it), published by
/// Cloudflare Pages, and served at your own domain. Steps that are set up for this site
/// say so.
struct HowItWorksCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        DashboardCard(title: "How CardStock Works",
                      subtitle: "Your website goes from your Mac to the world, with GitHub keeping every version safe in between.") {
            // Left to right when there's room; top to bottom otherwise.
            ViewThatFits(in: .horizontal) {
                wide
                narrow
            }
            HStack(spacing: 10) {
                Button("Set Up Publishing", systemImage: "arrow.up.circle") { model.selection = .publish }
                Button("Learn More", systemImage: "questionmark.circle") { model.showHelp("ways-to-publish") }
            }
            .controlSize(.small)
        }
    }

    // MARK: - Steps

    private var thisMac: FlowNode {
        FlowNode(icon: "laptopcomputer", color: .blue, title: "Your Mac",
                 detail: "Your site's files live in a folder here. Write and edit them in CardStock, even offline.",
                 status: .done("Editing now"))
    }

    private var anywhere: FlowNode {
        FlowNode(icon: "desktopcomputer", color: .teal, title: "Any Computer",
                 detail: "Open the site from GitHub on any Mac with CardStock and pick up where you left off.",
                 status: nil)
    }

    private var github: FlowNode {
        FlowNode(icon: "arrow.triangle.branch", color: .indigo, title: "GitHub",
                 detail: "The source of truth. Every publish is saved here, so every computer stays in step.",
                 status: model.project.github.map { .done($0.repo) } ?? .todo("Not linked yet"))
    }

    private var cloudflare: FlowNode {
        FlowNode(icon: "cloud.fill", color: .orange, title: "Cloudflare Pages",
                 detail: "Picks up each change on GitHub and puts your site online within a minute.",
                 status: model.websiteURL == nil ? .todo("Not set up yet") : .done("Online"))
    }

    private var domain: FlowNode {
        FlowNode(icon: "globe", color: .green, title: "Your Domain",
                 detail: "Cloudflare also looks after your domain name and HTTPS. No servers to worry about.",
                 status: model.websiteURL?.host().map { .done($0) })
    }

    // MARK: - Layouts

    /// Both computers on the left meet at GitHub, then on to Cloudflare and the world.
    private var wide: some View {
        HStack(spacing: 0) {
            VStack(spacing: 12) {
                thisMac
                anywhere
            }
            .frame(width: 158)
            .fixedSize(horizontal: false, vertical: true)
            FlowConnector(style: .merge, label: "Sync")
                .frame(width: 64)
            // The rest share one height, centered beside the two computers.
            HStack(spacing: 0) {
                github.frame(width: 158)
                FlowConnector(style: .across, label: "Deploy")
                    .frame(width: 64)
                cloudflare.frame(width: 158)
                FlowConnector(style: .across, label: "Serve")
                    .frame(width: 64)
                domain.frame(width: 158)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .fixedSize(horizontal: true, vertical: true)
        .frame(maxWidth: .infinity)
    }

    private var narrow: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                thisMac
                anywhere
            }
            .fixedSize(horizontal: false, vertical: true)
            FlowConnector(style: .down, label: "Sync").frame(height: 40)
            github
            FlowConnector(style: .down, label: "Deploy").frame(height: 40)
            cloudflare
            FlowConnector(style: .down, label: "Serve").frame(height: 40)
            domain
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
    }
}

/// One stop on the way: an icon, a name, what happens there, and whether it's set up.
private struct FlowNode: View {
    enum Status {
        case done(String)
        case todo(String)
    }

    let icon: String
    let color: Color
    let title: String
    let detail: String
    let status: Status?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 9))
                .shadow(color: color.opacity(0.3), radius: 5, y: 2)
            Text(title).font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let status { badge(status) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(color.opacity(0.25)))
    }

    private func badge(_ status: Status) -> some View {
        let (text, symbol, tint): (String, String, Color) = switch status {
        case .done(let text): (text, "checkmark.circle.fill", .green)
        case .todo(let text): (text, "circle.dashed", .secondary)
        }
        return Label(text, systemImage: symbol)
            .font(.caption2.weight(.medium))
            .foregroundStyle(tint)
            .lineLimit(2)
            .truncationMode(.middle)
    }
}

/// A dashed line between stops, with a label. The dashes drift along the way the site
/// travels (unless Reduce Motion is on).
private struct FlowConnector: View {
    enum Style {
        /// From two stacked stops on the left into one on the right, both ways (syncing).
        case merge
        /// Left to right.
        case across
        /// Top to bottom (the narrow layout).
        case down
    }

    let style: Style
    let label: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    var body: some View {
        ZStack {
            DashedPath(style: style, phase: phase)
                .fill(Color.secondary.opacity(0.7))
            arrowheads
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.background, in: Capsule())
                .offset(x: style == .down ? 34 : 0, y: style == .down ? 0 : -14)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { phase = -DashedPath.period }
        }
    }

    private var arrowheads: some View {
        GeometryReader { geometry in
            let size = geometry.size
            switch style {
            case .merge:
                // Into GitHub, and back out to both computers.
                arrow("chevron.right").position(x: size.width - 4, y: size.height / 2)
                arrow("chevron.left").position(x: 4, y: size.height * 0.25)
                arrow("chevron.left").position(x: 4, y: size.height * 0.75)
            case .across:
                arrow("chevron.right").position(x: size.width - 4, y: size.height / 2)
            case .down:
                arrow("chevron.down").position(x: size.width / 2, y: size.height - 4)
            }
        }
    }

    private func arrow(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
    }
}

/// The connector's line as filled dashes, so the dash offset can animate.
private struct DashedPath: Shape {
    static let period: CGFloat = 9

    let style: FlowConnector.Style
    var phase: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var line = Path()
        let inset: CGFloat = 6
        switch style {
        case .merge:
            let end = CGPoint(x: rect.maxX - inset, y: rect.midY)
            for y in [rect.height * 0.25, rect.height * 0.75] {
                let start = CGPoint(x: rect.minX + inset, y: y)
                line.move(to: start)
                line.addCurve(to: end, control1: CGPoint(x: rect.midX, y: y),
                              control2: CGPoint(x: rect.midX, y: rect.midY))
            }
        case .across:
            line.move(to: CGPoint(x: rect.minX + inset, y: rect.midY))
            line.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.midY))
        case .down:
            line.move(to: CGPoint(x: rect.midX, y: rect.minY + inset))
            line.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - inset))
        }
        return line.strokedPath(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, Self.period - 4], dashPhase: phase))
    }
}
