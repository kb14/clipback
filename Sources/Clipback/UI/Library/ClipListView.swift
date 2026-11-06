import ClipbackCore
import SwiftUI

struct ClipListView: View {
    let title: String
    let sections: [ClipSection]
    @Binding var selectedID: StoredClip.ID?
    /// When set, rows get a checkbox that marks the clip done.
    var onDone: ((StoredClip) -> Void)?
    /// Replaces the age shown at the right of each row, e.g. when a Revise clip comes back.
    var trailing: ((Clip) -> String)?

    var body: some View {
        List(selection: $selectedID) {
            ForEach(sections) { section in
                Section {
                    ForEach(section.clips) { stored in
                        HStack(alignment: .top, spacing: 8) {
                            if let onDone {
                                DoneCheckbox { onDone(stored) }
                                    .padding(.top, 3)
                            }
                            ClipRow(clip: stored.clip, trailing: trailing?(stored.clip))
                        }
                        .tag(stored.id)
                    }
                } header: {
                    HStack {
                        Text(section.title).lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 8)
                        if let detail = section.detail {
                            Text(detail).fontWeight(.regular).foregroundStyle(.tertiary).fixedSize()
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
        .navigationTitle(title)
        .onAppear(perform: keepSelection)
        .onChange(of: selectionIsMissing) { _, missing in if missing { keepSelection() } }
        .onChange(of: selectedID) { _, id in
            if let id, let index = ids.firstIndex(of: id) { selectedIndex = index }
        }
    }

    /// Where the selected clip sat, so when it leaves the list the clip that takes its place is selected.
    @State private var selectedIndex = 0

    private var ids: [StoredClip.ID] { sections.flatMap(\.clips).map(\.id) }

    /// Nothing selected while there are clips, or the selected clip left the list. Cheap to check on every render.
    private var selectionIsMissing: Bool {
        guard let selectedID else { return sections.contains { !$0.clips.isEmpty } }
        return !sections.contains { $0.clips.contains { $0.id == selectedID } }
    }

    /// When the selected clip leaves the list (archived, moved, deleted), select the one that took its place,
    /// so tidying up goes clip by clip like Mail.
    private func keepSelection() {
        guard selectionIsMissing else { return }
        let current = ids
        selectedID = selectedID == nil ? current.first : current.isEmpty ? nil : current[min(selectedIndex, current.count - 1)]
    }
}

struct ClipRow: View {
    let clip: Clip
    var trailing: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(nsImage: AppIcons.icon(bundleID: clip.source.bundleID, appName: clip.source.app))
                .resizable()
                .frame(width: 18, height: 18)
                .overlay(alignment: .bottomTrailing) {
                    // Screenshot clips get a small photo badge on the app icon rather than an icon in the text.
                    if clip.kind != .text {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 12, height: 12)
                            .background(Color.secondary, in: Circle())
                            .offset(x: 4, y: 4)
                    }
                }
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(clip.title.isEmpty ? "Untitled clip" : clip.title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(clip.isArchived ? .secondary : .primary)
                HStack(spacing: 6) {
                    if clip.isArchived {
                        ArchivedBadge(date: nil)
                    }
                    if clip.intent != .save {
                        IntentPill(intent: clip.intent, people: clip.people, isDone: clip.done != nil, maxNames: 2)
                    }
                    Text(SourceLabel.short(clip.source))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Text(trailing ?? clip.created.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .fixedSize()
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

/// Marks a clip that's finished with, e.g. in search results or its detail view.
struct ArchivedBadge: View {
    let date: Date?

    var body: some View {
        Label(date.map { "Archived \(Self.day($0))" } ?? "Archived", systemImage: "archivebox")
            .pill(.secondary, on: .quaternary)
    }

    /// Archive dates are stored as days, so this says "today" rather than a misleading number of hours.
    private static func day(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "today" }
        if calendar.isDateInYesterday(date) { return "yesterday" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}

/// Ticks a call or to-do off. Finished ones move to Archive, so the box is only ever shown empty.
struct DoneCheckbox: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "square")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Mark as done")
    }
}

struct IntentPill: View {
    let intent: Intent
    /// Everyone a Call clip is for. Other intents don't name people.
    var people: [String] = []
    /// Discussed or finished: a tick inside the pill.
    var isDone = false
    /// In tight spots, e.g. list rows, the rest collapse into "+2".
    var maxNames = Int.max

    var body: some View {
        let label = intent == .call && !people.isEmpty ? "\(intent.title) · \(names)" : intent.title
        Text(isDone ? "✓ \(label)" : label)
            .pill(intent.color, on: intent.color.opacity(0.15))
    }

    private var names: String {
        let shown = people.prefix(maxNames).joined(separator: ", ")
        return people.count > maxNames ? "\(shown) +\(people.count - maxNames)" : shown
    }
}

extension View {
    /// The small capsule label used in rows and headers, e.g. an intent or "Archived".
    func pill<Foreground: ShapeStyle, Background: ShapeStyle>(_ foreground: Foreground, on background: Background) -> some View {
        font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .fixedSize()
    }
}

/// Short human names for where a clip came from.
enum SourceLabel {
    /// The page title without the browser's name, else the file name, else the site or app.
    static func title(_ source: ClipSource) -> String {
        if let window = source.window, source.url != nil {
            let stripped = window.replacing(#/ [-–—] (Google Chrome|Safari|Brave|Microsoft Edge|Arc)( [-–—] .*)?$/#, with: "")
            if !stripped.isEmpty { return stripped }
        }
        if let file = source.file { return (file as NSString).lastPathComponent }
        return short(source)
    }

    static func short(_ source: ClipSource) -> String {
        if let url = source.url, let host = URL(string: url)?.host() {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        if let file = source.file {
            let name = (file as NSString).lastPathComponent
            return source.page.map { "\(name) · p\($0)" } ?? name
        }
        return source.app
    }
}

@MainActor
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(bundleID: String?, appName: String) -> NSImage {
        let key = bundleID ?? appName
        if let cached = cache[key] { return cached }
        let icon: NSImage
        if let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            icon = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: appName) ?? NSImage()
        }
        cache[key] = icon
        return icon
    }
}
