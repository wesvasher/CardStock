import SwiftUI

/// A page's tags as removable chips, a field to type new ones (Return or a
/// comma adds one), matching tags from the rest of the site to click, and a
/// menu of every tag.
struct TagEditor: View {
    @Binding var tags: [String]
    /// Every tag in the site, for suggestions.
    let suggestions: [String]
    @State private var text = ""
    @FocusState private var focused: Bool

    private func has(_ name: String) -> Bool {
        tags.contains { TagSettings.slug($0) == TagSettings.slug(name) }
    }

    /// Site tags this page doesn't have yet.
    private var available: [String] { suggestions.filter { !has($0) } }

    /// Tags that start with (or contain) what's typed.
    private var matches: [String] {
        let typed = text.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return [] }
        let starts = available.filter { $0.lowercased().hasPrefix(typed.lowercased()) }
        let contains = available.filter { !starts.contains($0) && $0.localizedCaseInsensitiveContains(typed) }
        return Array((starts + contains).prefix(6))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                FlowLayout(spacing: 4) {
                    ForEach(tags, id: \.self) { tag in chip(tag) }
                    TextField(tags.isEmpty ? "Add tags" : "Add a tag", text: $text)
                        .textFieldStyle(.plain)
                        .frame(width: 110)
                        .focused($focused)
                        .onSubmit { commit() }
                        .onChange(of: text) { _, new in
                            if new.contains(",") { commit() }
                        }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color(nsColor: .separatorColor)))
                .contentShape(Rectangle())
                .onTapGesture { focused = true }

                Menu {
                    if available.isEmpty {
                        Text(suggestions.isEmpty ? "No tags yet" : "Every tag is on this page")
                    }
                    ForEach(available, id: \.self) { name in
                        Button(name) { add(name) }
                    }
                } label: {
                    Image(systemName: "tag")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Add a tag used on other pages")
            }
            if !matches.isEmpty {
                HStack(spacing: 4) {
                    ForEach(matches, id: \.self) { name in
                        Button(name) { add(name) }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                    }
                }
            }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { commit() }
        }
        .onDisappear { commit() }
    }

    private func chip(_ tag: String) -> some View {
        HStack(spacing: 3) {
            Text(tag)
                .lineLimit(1)
            Button {
                tags.removeAll { $0 == tag }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove “\(tag)”")
        }
        .font(.callout)
        .padding(.leading, 7)
        .padding(.trailing, 5)
        .padding(.vertical, 1)
        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
    }

    /// Adds what's typed (split at commas). A tag the site already has is
    /// added the way it's written there.
    private func commit() {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        text = ""
        for part in parts { add(part) }
    }

    private func add(_ name: String) {
        let existing = suggestions.first { TagSettings.slug($0) == TagSettings.slug(name) } ?? name
        if !has(existing) { tags.append(existing) }
        if text.trimmingCharacters(in: .whitespaces).lowercased() == name.lowercased() { text = "" }
    }
}
