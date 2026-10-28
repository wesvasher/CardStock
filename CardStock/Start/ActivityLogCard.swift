import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Status → Activity Log: everything that happened in CardStock (edits,
/// publishing, the host's builds, errors), in a card that fills the height
/// it's given, with the entries scrolling inside. Shows this
/// site's entries (and app-wide ones) unless All Sites is on. Entries can be
/// filtered, searched, exported as text and deleted.
struct ActivityLogCard: View {
    @Environment(AppModel.self) private var model
    @AppStorage("activityLogAllSites") private var allSites = false
    @State private var filter = Filter.all
    @State private var search = ""
    @State private var shownCount = 150
    @State private var confirmDelete = false

    enum Filter: String, CaseIterable, Identifiable {
        case all, edits, publishing, problems
        var id: Self { self }
        var title: String {
            switch self {
            case .all: "All"
            case .edits: "Edits"
            case .publishing: "Publishing"
            case .problems: "Problems"
            }
        }
    }

    private var sitePath: String? { model.site?.root.path }

    /// Entries for this site (or every site), newest first.
    private var siteEntries: [LogEntry] {
        model.activityLog.entries.reversed().filter { entry in
            allSites || entry.sitePath == nil || entry.sitePath == sitePath
        }
    }

    private var visible: [LogEntry] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return siteEntries.filter { entry in
            let kindMatches = switch filter {
            case .all: true
            case .edits: entry.kind == .edit
            case .publishing: entry.kind == .publish || entry.kind == .hosting
            case .problems: entry.isProblem
            }
            guard kindMatches else { return false }
            guard !query.isEmpty else { return true }
            return [entry.message, entry.detail ?? "", entry.site ?? ""].contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            controls
            list
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
        .confirmationDialog("Delete the activity log?", isPresented: $confirmDelete) {
            if let sitePath {
                Button("Delete This Site's Entries", role: .destructive) { model.activityLog.clear(sitePath: sitePath) }
            }
            Button("Delete Entire Log", role: .destructive) { model.activityLog.clear() }
        } message: {
            Text("Deleted entries can't be brought back. Export the log first to keep a copy.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Activity Log").font(.headline)
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            if problemsToday > 0 {
                Label("\(problemsToday)", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .help("Problems in the last 24 hours")
            }
            Button("Export…", systemImage: "square.and.arrow.up", action: export)
                .labelStyle(.iconOnly)
                .disabled(visible.isEmpty)
                .help("Save the entries shown as a text file")
            Button("Delete…", systemImage: "trash") { confirmDelete = true }
                .labelStyle(.iconOnly)
                .disabled(model.activityLog.entries.isEmpty)
                .help("Delete entries from the log")
        }
        .buttonStyle(.borderless)
    }

    private var problemsToday: Int {
        let since = Date.now.addingTimeInterval(-86_400)
        return siteEntries.prefix { $0.date > since }.filter(\.isProblem).count
    }

    private var summary: String {
        guard let latest = siteEntries.first else {
            return "Everything you do in CardStock, publishing, website builds and errors."
        }
        return "Latest: \(latest.message), \(latest.date.formatted(.relative(presentation: .named)))"
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Show", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            HStack(spacing: 10) {
                TextField("Search", text: $search)
                    .textFieldStyle(.roundedBorder)
                Toggle("All Sites", isOn: $allSites)
                    .toggleStyle(.checkbox)
                    .help("Show entries from every site, not just this one")
            }
        }
        .controlSize(.small)
        .onChange(of: filter) { shownCount = 150 }
        .onChange(of: search) { shownCount = 150 }
    }

    // MARK: - Entries

    @ViewBuilder
    private var list: some View {
        let entries = visible
        if entries.isEmpty {
            Text(siteEntries.isEmpty ? "Nothing logged yet." : "No entries match.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    ForEach(days(Array(entries.prefix(shownCount))), id: \.day) { group in
                        Section {
                            ForEach(group.entries) { entry in
                                LogRow(entry: entry, showSite: allSites)
                                Divider().opacity(0.5)
                            }
                        } header: {
                            Text(group.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                                .background(.background.opacity(0.95))
                        }
                    }
                    if entries.count > shownCount {
                        Button("Show \(min(150, entries.count - shownCount)) More") { shownCount += 150 }
                            .buttonStyle(.link)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private struct Day {
        var day: Date
        var title: String
        var entries: [LogEntry]
    }

    private func days(_ entries: [LogEntry]) -> [Day] {
        let calendar = Calendar.current
        var result: [Day] = []
        for entry in entries {
            let day = calendar.startOfDay(for: entry.date)
            if result.last?.day == day {
                result[result.count - 1].entries.append(entry)
            } else {
                let title = calendar.isDateInToday(day) ? "Today"
                    : calendar.isDateInYesterday(day) ? "Yesterday"
                    : day.formatted(date: .complete, time: .omitted)
                result.append(Day(day: day, title: title, entries: [entry]))
            }
        }
        return result
    }

    private func export() {
        let panel = NSSavePanel()
        panel.title = "Export Activity Log"
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "CardStock Activity Log \(Date.now.formatted(.iso8601.year().month().day())).txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ActivityLog.exportText(visible.reversed()).write(to: url, atomically: true, encoding: .utf8)
            model.showToast("Exported \(visible.count) log entries.")
        } catch {
            model.errorMessage = "Couldn't export the activity log: \(error.localizedDescription)"
        }
    }
}

/// One entry: what happened, when, and any details or link.
private struct LogRow: View {
    let entry: LogEntry
    let showSite: Bool
    @State private var expanded = false

    private var tint: Color {
        if entry.isProblem { return .red }
        switch entry.kind {
        case .hosting: return .green
        case .publish: return .blue
        case .edit: return .orange
        case .app, .error: return .secondary
        }
    }

    private var symbol: String {
        if entry.kind == .hosting { return entry.failed ? "xmark.icloud" : "checkmark.icloud" }
        return entry.kind.systemImage
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.message)
                    .font(.callout)
                    .fontWeight(entry.isProblem ? .medium : .regular)
                    .textSelection(.enabled)
                if let detail = entry.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(expanded ? nil : 2)
                        .textSelection(.enabled)
                        .onTapGesture { expanded.toggle() }
                }
                HStack(spacing: 10) {
                    if showSite, let site = entry.site {
                        Text(site).font(.caption2).foregroundStyle(.tertiary)
                    }
                    if let link = entry.link, let url = URL(string: link) {
                        Button(entry.kind == .hosting ? "View Build" : "Open") { NSWorkspace.shared.open(url) }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
            }
            Spacer(minLength: 8)
            Text(entry.date.formatted(date: .omitted, time: .shortened))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .help(entry.date.formatted(date: .complete, time: .standard))
        }
        .padding(.vertical, 7)
    }
}
