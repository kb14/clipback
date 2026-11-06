import ClipbackCore
import SwiftUI

enum SidebarItem: Hashable {
    case today
    case inbox
    case revise
    case calls
    case todo
    case sources
    /// Finished clips: put away by hand, discussed, done or retired.
    case archive
    /// Every clip from one page or file, by `SourceKey`.
    case source(String)
    case tag(String)
}

/// Where the review window is. Shared so the menubar can open it straight to Today or Calls.
@MainActor
@Observable
final class LibraryNavigation {
    static let shared = LibraryNavigation()
    var sidebar: SidebarItem? = .inbox
    var selectedID: StoredClip.ID?
    var person: String?
    var query = ""
    /// Clip to select after the next sidebar change, e.g. when jumping to "More from this page".
    var pendingSelection: StoredClip.ID?

    func show(_ item: SidebarItem, selecting id: StoredClip.ID? = nil) {
        pendingSelection = id
        sidebar = item
    }
}

/// The review window: sidebar of views and tags, then either a list with the selected clip, Today's revision
/// card, or a person's call agenda.
struct LibraryView: View {
    @State private var library = ClipLibrary.shared
    @State private var navigation = LibraryNavigation.shared
    @FocusState private var searchFocused: Bool
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        NavigationSplitView {
            SidebarView(library: library, selection: $navigation.sidebar)
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            main
                .overlay(alignment: .bottom) {
                    if let event = library.lastArchived {
                        UndoArchiveBar(event: event, library: library)
                            .padding(.bottom, 18)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.2), value: library.lastArchived)
                // Archiving joins the window's undo stack, so Edit > Undo (⌘Z) takes back the latest thing done,
                // whether that's typing in a note or archiving a clip.
                .onChange(of: library.lastArchived) { _, event in
                    guard let event else { return }
                    undoManager?.registerUndo(withTarget: library) { library in
                        MainActor.assumeIsolated { library.undo(event) }
                    }
                    undoManager?.setActionName("Archive")
                }
        }
        .searchable(text: $navigation.query, placement: .sidebar, prompt: "Search")
        .searchFocused($searchFocused)
        .background {
            // ⌘F and ⌘K both jump to search.
            Button("") { searchFocused = true }.keyboardShortcut("f").hidden()
            Button("") { searchFocused = true }.keyboardShortcut("k").hidden()
        }
        .onChange(of: navigation.sidebar) { _, _ in
            navigation.query = ""
            navigation.selectedID = navigation.pendingSelection
            navigation.pendingSelection = nil
        }
        .onChange(of: library.library) { _, _ in navigation.sidebar = .inbox; navigation.selectedID = nil }
        .frame(minWidth: 900, minHeight: 560)
    }

    @ViewBuilder
    private var main: some View {
        if isSearching {
            listAndDetail(title: "Search", sections: ClipSection.byDay(library.clips.filter { ClipSearch.matches($0.clip, query: navigation.query) }),
                          empty: .search(navigation.query))
        } else {
            switch navigation.sidebar {
            case .today:
                TodayView(library: library, keysEnabled: !searchFocused)
            case .calls:
                CallsView(library: library, person: $navigation.person)
            case .revise:
                listAndDetail(title: "Revise", sections: ReviseSections.make(library.activeClips),
                              empty: .revise,
                              trailing: ReviseSections.whenNext)
            case .todo:
                let open = library.activeClips.filter { $0.clip.intent == .todo }
                listAndDetail(title: "To-do", sections: open.isEmpty ? [] : [ClipSection(title: "Open", clips: open)],
                              empty: .todo, showsCheckbox: true)
            case .sources:
                listAndDetail(title: "Sources", sections: SourceSections.make(library.activeClips),
                              empty: .sources)
            case .source(let key):
                let clips = library.activeClips.filter { SourceKey.key(for: $0.clip.source) == key }
                listAndDetail(title: clips.first.map { SourceLabel.title($0.clip.source) } ?? "Source",
                              sections: ClipSection.byDay(clips), empty: .none)
            case .tag(let tag):
                listAndDetail(title: "#\(tag)", sections: ClipSection.byDay(library.activeClips.filter { $0.clip.tags.contains(tag) }), empty: .none)
            case .archive:
                listAndDetail(title: "Archive", sections: ClipSection.byDay(library.archivedClips, date: { $0.archivedOn ?? $0.created }),
                              empty: .archive)
            case .inbox, nil:
                listAndDetail(title: "Inbox", sections: ClipSection.byDay(library.activeClips), empty: .inbox)
            }
        }
    }

    private var isSearching: Bool { !navigation.query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// A fixed-width list beside the selected clip. Plain stacks rather than a split view, so each column is
    /// exactly as tall as the window and the clip scrolls inside it.
    @ViewBuilder
    private func listAndDetail(title: String, sections: [ClipSection], empty: EmptyState, showsCheckbox: Bool = false,
                               trailing: ((Clip) -> String)? = nil) -> some View {
        if sections.isEmpty {
            EmptyStateView(state: empty).navigationTitle(title)
        } else {
            split(title: title, sections: sections, showsCheckbox: showsCheckbox, trailing: trailing)
        }
    }

    private func split(title: String, sections: [ClipSection], showsCheckbox: Bool, trailing: ((Clip) -> String)?) -> some View {
        HStack(spacing: 0) {
            ClipListView(title: title, sections: sections, selectedID: $navigation.selectedID,
                         onDone: showsCheckbox ? { library.markDone([$0]) } : nil,
                         trailing: trailing)
                .frame(width: 330)
                .frame(maxHeight: .infinity)
            Divider()
            Group {
                if let stored = sections.lazy.flatMap(\.clips).first(where: { $0.id == navigation.selectedID }) {
                    ClipDetailView(stored: stored, library: library).id(stored.id)
                } else {
                    Text(library.clips.isEmpty ? "" : "Select a clip")
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// "Archived … · Undo" for a few seconds after something is archived, then it goes away on its own.
private struct UndoArchiveBar: View {
    let event: ClipLibrary.ArchiveEvent
    let library: ClipLibrary
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "archivebox").foregroundStyle(.secondary)
            Text("Archived \(event.title)").lineLimit(1).truncationMode(.tail)
            Button("Undo") {
                library.undo(event)
                undoManager?.removeAllActions(withTarget: library)
            }
            .buttonStyle(.link)
        }
        .toastCapsule()
        .frame(maxWidth: 520)
        .task(id: event.at) {
            try? await Task.sleep(for: .seconds(6))
            if library.lastArchived == event { library.clearArchiveEvent() }
        }
    }
}

/// Revise clips still in rotation: what's due, then what's coming up soonest first. Retired ones are in Archive.
enum ReviseSections {
    static func make(_ clips: [StoredClip], now: Date = Date(), calendar: Calendar = .current) -> [ClipSection] {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        func next(_ stored: StoredClip) -> Date { stored.clip.review?.next ?? stored.clip.created }
        let active = clips.filter { $0.clip.intent == .revise }.sorted { next($0) < next($1) }
        let sections = [
            ClipSection(title: "Due today", clips: active.filter { next($0) < tomorrow }),
            ClipSection(title: "Coming up", clips: active.filter { next($0) >= tomorrow }),
        ]
        return sections.filter { !$0.clips.isEmpty }
    }

    /// "today", "tomorrow" or "in 3 days", shown at the right of each row.
    static func whenNext(_ clip: Clip) -> String {
        clip.review?.whenNext() ?? "today"
    }
}

/// One section per page or file, the most recently clipped first. Clips with no page or file are left out.
enum SourceSections {
    static func make(_ clips: [StoredClip]) -> [ClipSection] {
        var order: [String] = []
        var groups: [String: [StoredClip]] = [:]
        for stored in clips {
            guard let key = SourceKey.key(for: stored.clip.source) else { continue }
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(stored)
        }
        return order.map { key in
            let members = groups[key] ?? []
            let title = members.first.map { SourceLabel.title($0.clip.source) } ?? key
            return ClipSection(title: title, clips: members, id: key,
                               detail: "\(members.count) \(members.count == 1 ? "clip" : "clips")")
        }
    }
}

struct ClipSection: Identifiable {
    var title: String
    var clips: [StoredClip]
    var id: String
    /// Shown at the right of the section header, e.g. a clip count.
    var detail: String?

    init(title: String, clips: [StoredClip], id: String? = nil, detail: String? = nil) {
        self.title = title
        self.clips = clips
        self.id = id ?? title
        self.detail = detail
    }

    /// Today, Yesterday, This week, then month by month. Clips arrive newest first.
    static func byDay(_ clips: [StoredClip], date: (Clip) -> Date = \.created, now: Date = Date(),
                      calendar: Calendar = .current) -> [ClipSection] {
        var sections: [ClipSection] = []
        for stored in clips {
            let title = bucket(for: date(stored.clip), now: now, calendar: calendar)
            if sections.last?.title == title {
                sections[sections.count - 1].clips.append(stored)
            } else {
                sections.append(ClipSection(title: title, clips: [stored]))
            }
        }
        return sections
    }

    private static func bucket(for date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days < 7 { return "This week" }
        return date.formatted(.dateTime.month(.wide).year())
    }
}

private struct SidebarView: View {
    @Bindable var library: ClipLibrary
    @Binding var selection: SidebarItem?

    var body: some View {
        let clips = library.activeClips
        List(selection: $selection) {
            Picker("Library", selection: $library.library) {
                ForEach(Library.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.bottom, 6)

            Section {
                row(.today, "Today", "sun.max", count: library.today(in: library.library).due.count, highlighted: true)
                row(.inbox, "Inbox", "tray", count: clips.count)
                row(.revise, "Revise", "repeat", count: clips.filter { $0.clip.intent == .revise }.count)
                row(.calls, "Calls", "phone", count: clips.filter { $0.clip.intent == .call }.count)
                row(.todo, "To-do", "checkmark.square", count: clips.filter { $0.clip.intent == .todo }.count)
                row(.sources, "Sources", "link", count: Set(clips.compactMap { SourceKey.key(for: $0.clip.source) }).count)
                row(.archive, "Archive", "archivebox", count: library.archivedCount)
            }

            if !topTags.isEmpty {
                Section("Tags") {
                    ForEach(topTags, id: \.tag) { item in
                        row(.tag(item.tag), item.tag, "number", count: item.count)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ item: SidebarItem, _ title: String, _ symbol: String, count: Int, highlighted: Bool = false) -> some View {
        Label {
            HStack {
                Text(title)
                Spacer()
                if count > 0 {
                    if highlighted {
                        Text("\(count)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .background(Intent.revise.color, in: Capsule())
                    } else {
                        Text("\(count)").foregroundStyle(.tertiary).monospacedDigit()
                    }
                }
            }
        } icon: {
            Image(systemName: symbol)
        }
        .tag(item)
    }

    /// The most used tags, so the sidebar fills itself in with no setup.
    private var topTags: [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for stored in library.activeClips {
            for tag in stored.clip.tags { counts[tag, default: 0] += 1 }
        }
        return counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(12).map { (tag: $0.key, count: $0.value) }
    }
}
