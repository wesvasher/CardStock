import Charts
import SwiftUI

/// Chart colors: one blue ramp (light → dark for more activity on a light
/// background, the reverse on dark), from the validated reference palette.
enum DashboardColors {
    private static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }

    /// Calendar steps for 1, 2, 3–4 and 5+ things in a day. The step next to
    /// the background still stands out from it.
    static func level(_ level: Int, dark: Bool) -> Color {
        let light: [UInt32] = [0x86B6EF, 0x3987E5, 0x1C5CAB, 0x0D366B]
        let darkSteps: [UInt32] = [0x184F95, 0x2A78D6, 0x6DA7EC, 0xB7D3F6]
        return rgb((dark ? darkSteps : light)[max(0, min(3, level - 1))])
    }

    static func bar(dark: Bool) -> Color { rgb(dark ? 0x3987E5 : 0x2A78D6) }

    /// Empty calendar days: a faint wash, not a color.
    static let empty = Color.primary.opacity(0.07)
}

/// A rounded panel holding one part of the dashboard.
struct DashboardCard<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
        .padding(18)
        // Fills the height it's given, so cards side by side can match.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Activity calendar

/// A year of publishing as a grid of days, darker for busier days. Each
/// square shows its date and count on hover.
struct ActivityCalendarCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    private let cell: CGFloat = 12
    private let gap: CGFloat = 3
    private let labelWidth: CGFloat = 28
    private var calendar: Calendar { .current }

    private var noun: (String, String) {
        model.activityIsPublishes ? ("publish", "publishes") : ("post", "posts")
    }

    var body: some View {
        let counts = SiteInsights.dailyCounts(model.activityDates)
        DashboardCard(title: "Publishing Activity", subtitle: subtitle) {
            GeometryReader { geo in
                let weeks = max(8, min(53, Int((geo.size.width - labelWidth) / (cell + gap))))
                grid(counts: counts, weeks: weeks)
            }
            .frame(height: 7 * (cell + gap) + 18)
            legend
        }
    }

    private var subtitle: String {
        let yearAgo = calendar.date(byAdding: .year, value: -1, to: .now) ?? .distantPast
        let lastYear = model.activityDates.filter { $0 >= yearAgo }.count
        var parts = ["\(lastYear) \(lastYear == 1 ? noun.0 : noun.1) in the last year"]
        if let site = model.site,
           let latest = SiteInsights.postDates(site).max() {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: latest),
                                               to: calendar.startOfDay(for: .now)).day ?? 0
            parts.append(days <= 0 ? "last post today" : days == 1 ? "last post yesterday" : "last post \(days) days ago")
        }
        let streak = SiteInsights.weekStreak(model.activityDates)
        if streak > 1 { parts.append("\(streak)-week streak") }
        return parts.joined(separator: " · ")
    }

    /// Columns of weeks (oldest on the left), Sunday or Monday at the top
    /// depending on the Mac's settings, with month names above.
    private func grid(counts: [Date: Int], weeks: Int) -> some View {
        let today = calendar.startOfDay(for: .now)
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let firstWeek = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek) ?? thisWeek
        let columns = (0..<weeks).compactMap { calendar.date(byAdding: .weekOfYear, value: $0, to: firstWeek) }
        let dayFormatter = Date.FormatStyle.dateTime.weekday(.wide).month(.abbreviated).day().year()

        return VStack(alignment: .leading, spacing: 4) {
            // Month names over the first week of each month.
            HStack(spacing: gap) {
                Color.clear.frame(width: labelWidth - gap, height: 12)
                ForEach(columns.indices, id: \.self) { i in
                    let month = calendar.component(.month, from: columns[i])
                    let isNew = i == 0 || calendar.component(.month, from: columns[i - 1]) != month
                    Text(isNew && i < columns.count - 2 ? columns[i].formatted(.dateTime.month(.abbreviated)) : "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .frame(width: cell, height: 12, alignment: .leading)
                }
            }
            HStack(alignment: .top, spacing: gap) {
                // Every other weekday name, like most calendars of this kind.
                VStack(alignment: .leading, spacing: gap) {
                    ForEach(0..<7, id: \.self) { row in
                        let date = calendar.date(byAdding: .day, value: row, to: thisWeek) ?? thisWeek
                        Text(row % 2 == 1 ? date.formatted(.dateTime.weekday(.abbreviated)) : "")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: labelWidth - gap, height: cell, alignment: .leading)
                    }
                }
                ForEach(columns, id: \.self) { weekStart in
                    VStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { row in
                            let day = calendar.date(byAdding: .day, value: row, to: weekStart) ?? weekStart
                            if day > today {
                                Color.clear.frame(width: cell, height: cell)
                            } else {
                                let count = counts[day] ?? 0
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(color(for: count))
                                    .frame(width: cell, height: cell)
                                    .help("\(day.formatted(dayFormatter)): " +
                                          (count == 0 ? "nothing published" : "\(count) \(count == 1 ? noun.0 : noun.1)"))
                                    .accessibilityLabel("\(day.formatted(dayFormatter)), \(count) \(count == 1 ? noun.0 : noun.1)")
                            }
                        }
                    }
                }
            }
        }
    }

    private func color(for count: Int) -> Color {
        let level = switch count {
        case 0: 0
        case 1: 1
        case 2: 2
        case 3...4: 3
        default: 4
        }
        return level == 0 ? DashboardColors.empty : DashboardColors.level(level, dark: scheme == .dark)
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text(model.activityIsPublishes ? "From your publish history" : "From your posts' dates")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("Less").font(.caption).foregroundStyle(.secondary)
            RoundedRectangle(cornerRadius: 3).fill(DashboardColors.empty).frame(width: cell, height: cell)
            ForEach(1...4, id: \.self) { level in
                RoundedRectangle(cornerRadius: 3)
                    .fill(DashboardColors.level(level, dark: scheme == .dark))
                    .frame(width: cell, height: cell)
            }
            Text("More").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Writing

/// Headline numbers, posts per month, and the most used tags.
struct WritingCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    let site: Site
    @State private var hoveredMonth: Date?

    var body: some View {
        let stats = SiteInsights.writingStats(site)
        let months = SiteInsights.postsPerMonth(site)
        DashboardCard(title: "Writing") {
            HStack(alignment: .top, spacing: 0) {
                stat("\(stats.publishedPosts)", stats.publishedPosts == 1 ? "published post" : "published posts")
                stat(stats.totalWords.formatted(), "words written")
                stat(stats.averageReadingMinutes > 0 ? "\(stats.averageReadingMinutes) min" : "–", "average read")
            }

            if stats.drafts > 0 {
                draftsRow(stats)
            }

            Divider()
            monthChart(months)

            if !stats.topTags.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Top tags").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    FlowingTags(tags: stats.topTags)
                }
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title.bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func draftsRow(_ stats: SiteInsights.WritingStats) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil.and.outline").foregroundStyle(.orange)
            if let oldest = stats.oldestDraft {
                Text("\(stats.drafts) \(stats.drafts == 1 ? "draft" : "drafts") in progress · oldest is “\(oldest.title)”")
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Button("Finish It") { model.selection = .item(oldest.id) }
                    .buttonStyle(.link)
                    .font(.callout.weight(.medium))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Posts published each month over the past year. Hover a month for its count.
    private func monthChart(_ months: [(month: Date, count: Int)]) -> some View {
        let total = months.reduce(0) { $0 + $1.count }
        let peak = months.map(\.count).max() ?? 0
        let step = max(1, Int((Double(peak) / 3).rounded(.up)))
        let hovered = hoveredMonth.flatMap { h in
            months.first { Calendar.current.isDate($0.month, equalTo: h, toGranularity: .month) }
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Posts per month").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(hovered.map { "\($0.month.formatted(.dateTime.month(.wide).year())): \($0.count) \($0.count == 1 ? "post" : "posts")" }
                     ?? "\(total) in the last 12 months")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Chart(months, id: \.month) { entry in
                BarMark(x: .value("Month", entry.month, unit: .month),
                        y: .value("Posts", entry.count))
                    .foregroundStyle(DashboardColors.bar(dark: scheme == .dark)
                        .opacity(hovered == nil || hovered?.month == entry.month ? 1 : 0.45))
                    .cornerRadius(3)
            }
            .chartYScale(domain: 0...max(step * 3, 1))
            .chartYAxis {
                AxisMarks(position: .leading, values: .stride(by: Double(step))) { _ in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel().foregroundStyle(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated)).foregroundStyle(.secondary)
                }
            }
            .chartXSelection(value: $hoveredMonth)
            .frame(height: 110)
            .accessibilityLabel("Posts per month for the last 12 months")
        }
    }
}

/// Tag chips that wrap onto more lines when needed.
private struct FlowingTags: View {
    let tags: [(tag: String, count: Int)]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.tag) { item in
                HStack(spacing: 4) {
                    Text(item.tag)
                    Text("\(item.count)").foregroundStyle(.secondary).monospacedDigit()
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.07), in: Capsule())
            }
        }
    }
}

/// Lays children out in rows, wrapping when a row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Health

/// A checklist of common problems, each with a way to fix it.
struct HealthCard: View {
    @Environment(AppModel.self) private var model
    let site: Site

    var body: some View {
        let checks = SiteInsights.healthChecks(site, files: model.files, outdatedThemeFiles: model.outdatedThemeFiles)
        let failing = checks.filter { !$0.passed }
        DashboardCard(title: "Site Health") {
            summary(failing)
            VStack(spacing: 6) {
                ForEach(checks) { check in
                    CheckRow(check: check, onFix: perform)
                }
            }
        }
    }

    private func summary(_ failing: [SiteInsights.Check]) -> some View {
        let critical = failing.contains { $0.severity == .critical }
        let problems = failing.reduce(0) { $0 + $1.problems.count }
        return HStack(spacing: 10) {
            Image(systemName: failing.isEmpty ? "checkmark.seal.fill" : critical ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 26))
                .foregroundStyle(failing.isEmpty ? Color.green : critical ? Color.red : Color.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(failing.isEmpty ? "All good" : "\(problems) \(problems == 1 ? "thing" : "things") to fix")
                    .font(.title3.bold())
                Text(failing.isEmpty ? "Nothing needs your attention." : "Click a check to see what and where.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func perform(_ action: SiteInsights.Action) {
        switch action {
        case .openItem(let id): model.selection = .item(id)
        case .siteDetails: model.showConfiguration(.site)
        case .menu: model.showConfiguration(.topBar)
        case .newsletter: model.showConfiguration(.newsletter)
        case .folders: model.showConfiguration(.folders)
        case .footer: model.showConfiguration(.footer)
        case .files: model.selection = .files
        case .theming: model.showConfiguration(.templates)
        }
    }
}

private struct CheckRow: View {
    let check: SiteInsights.Check
    let onFix: (SiteInsights.Action) -> Void
    @State private var isExpanded = false

    private var icon: (String, Color, String) {
        if check.passed { return ("checkmark.circle.fill", .green, "Passed") }
        return check.severity == .critical
            ? ("xmark.octagon.fill", .red, "Needs fixing")
            : ("exclamationmark.triangle.fill", .orange, "Worth a look")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                guard !check.passed else { return }
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon.0)
                        .foregroundStyle(icon.1)
                        .accessibilityLabel(icon.2)
                    Text(check.title).font(.callout.weight(.medium))
                    Spacer()
                    Text(check.passed ? "OK" : "\(check.problems.count)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if !check.passed {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(check.passed ? check.passText : "Show what to fix")

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(check.problems.prefix(8)) { problem in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(problem.text)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            Button("Fix") { onFix(problem.action) }
                                .buttonStyle(.link)
                                .font(.caption.weight(.medium))
                        }
                    }
                    if check.problems.count > 8 {
                        Text("and \(check.problems.count - 8) more")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.leading, 26)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 4)
    }
}
