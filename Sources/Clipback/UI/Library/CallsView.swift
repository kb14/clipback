import AppKit
import ClipbackCore
import SwiftUI

/// People you have things to raise with, and the agenda for the selected person.
struct CallsView: View {
    let library: ClipLibrary
    @Binding var person: String?

    private static let unassigned = "Not assigned"

    var body: some View {
        let open = library.activeClips.filter { $0.clip.intent == .call }
        let people = Self.people(in: open)
        Group {
            if open.isEmpty {
                EmptyStateView(state: library.clips.contains { $0.clip.intent == .call } ? .callsDiscussed : .calls)
            } else {
                HStack(spacing: 0) {
                    List(selection: $person) {
                        Section("\(people.count) \(people.count == 1 ? "person" : "people")") {
                            ForEach(people, id: \.name) { entry in
                                HStack(spacing: 10) {
                                    Group {
                                        if entry.name == Self.unassigned {
                                            Image(systemName: "person.fill.questionmark").font(.system(size: 11))
                                        } else {
                                            Text(String(displayName(entry.name).prefix(1))).font(.system(size: 12, weight: .semibold))
                                        }
                                    }
                                    .foregroundStyle(.white)
                                    .frame(width: 24, height: 24)
                                    .background(entry.name == Self.unassigned ? Color.secondary.opacity(0.5) : Intent.call.color, in: Circle())
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(displayName(entry.name)).fontWeight(.medium)
                                        Text("\(entry.count) to raise").font(.system(size: 11.5)).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                                .tag(entry.name)
                            }
                        }
                    }
                    .listStyle(.inset)
                    .frame(width: 260)
                    .frame(maxHeight: .infinity)
                    Divider()

                    AgendaView(library: library, person: displayName(person ?? people.first?.name ?? Self.unassigned),
                               open: items(for: person ?? people.first?.name, in: open))
                        .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                }
                .onAppear {
                    if person == nil || !people.contains(where: { $0.name == person }) { person = people.first?.name }
                }
            }
        }
        .navigationTitle("Calls")
    }

    /// Full name from the library's people.json, e.g. "AlexStone" → "Alex Stone".
    private func displayName(_ handle: String) -> String {
        PeopleStore.people(in: library.library).first { $0.handle.caseInsensitiveCompare(handle) == .orderedSame }?.name ?? handle
    }

    /// Everyone a Call clip is for: its person plus anyone else @mentioned in the note.
    private static func handles(of clip: Clip) -> [String] {
        clip.people.isEmpty ? [unassigned] : clip.people
    }

    private func items(for person: String?, in clips: [StoredClip]) -> [StoredClip] {
        let wanted = person ?? Self.unassigned
        return clips.filter { Self.handles(of: $0.clip).contains { $0.caseInsensitiveCompare(wanted) == .orderedSame } }
            .sorted { $0.clip.created < $1.clip.created }
    }

    /// Most open items first; clips without an @person last.
    private static func people(in open: [StoredClip]) -> [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for stored in open {
            for name in handles(of: stored.clip) { counts[name, default: 0] += 1 }
        }
        return counts.map { (name: $0.key, count: $0.value) }.sorted { lhs, rhs in
            if lhs.name == unassigned { return false }
            if rhs.name == unassigned { return true }
            return (lhs.count, rhs.name) > (rhs.count, lhs.name)
        }
    }
}

private struct AgendaView: View {
    let library: ClipLibrary
    let person: String
    let open: [StoredClip]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(person).font(.title2.weight(.semibold))
                HStack(spacing: 8) {
                    Button {
                        copyAgenda()
                    } label: {
                        Label("Copy as agenda", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(open.isEmpty)
                    Button("Mark all discussed") { library.markDone(open) }
                    .disabled(open.isEmpty)
                }

                if open.isEmpty {
                    Text("Nothing left to raise with \(person)").foregroundStyle(.secondary).padding(.top, 8)
                }
                ForEach(Array(open.enumerated()), id: \.element.id) { index, stored in
                    AgendaItem(number: index + 1, stored: stored) { library.markDone([stored]) }
                }

            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func copyAgenda() {
        let text = Agenda.markdown(person: person, clips: open.map(\.clip), date: Date())
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Toast.shared.show("Copied \(person)'s agenda")
    }
}

/// One thing to raise, drawn like a compact version of the clip's detail: formatted text for text clips, the
/// image for screenshots. The title opens the full clip.
private struct AgendaItem: View {
    let number: Int
    let stored: StoredClip
    let onDone: () -> Void
    @State private var expanded = false
    @State private var showsImageText = false
    @State private var enlarged: NSImage?

    private var clip: Clip { stored.clip }
    private static let previewBlocks = 8

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DoneCheckbox(action: onDone)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 10) {
                header
                content
                sourceLine
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
        }
        .sheet(item: Binding(get: { enlarged.map(EnlargedImage.init) }, set: { enlarged = $0?.image })) { item in
            EnlargedImageView(image: item.image) { enlarged = nil }
        }
    }

    /// Your note is the agenda line; without one, the clip's title is.
    private var header: some View {
        let note = NoteParser.readable(clip.note)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(number).").foregroundStyle(.tertiary).monospacedDigit()
            Button {
                LibraryNavigation.shared.show(.inbox, selecting: stored.id)
            } label: {
                Text(note.isEmpty ? clip.title : note)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            .help("Open this clip")
            Spacer(minLength: 8)
            if clip.people.count > 1 {
                Text(clip.people.joined(separator: ", "))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Intent.call.color)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if clip.kind == .text {
            let blocks = MarkdownBlocks.parse(clip.selection).count
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color.highlight).frame(width: 3)
                VStack(alignment: .leading, spacing: 6) {
                    MarkdownText(text: clip.selection, size: 13.5, design: .serif, maxBlocks: expanded ? nil : Self.previewBlocks)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if blocks > Self.previewBlocks {
                        Button(expanded ? "Show less" : "Show more") { expanded.toggle() }
                            .buttonStyle(.link)
                            .font(.system(size: 12))
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        } else if let url = stored.imageURL, let image = NSImage(contentsOf: url) {
            VStack(alignment: .leading, spacing: 6) {
                Button { enlarged = image } label: {
                    // Sized exactly to the image, so the border and corners hug it.
                    let size = Self.fitted(image.size, maxWidth: 520, maxHeight: 260)
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: size.width, height: size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .help("Click to enlarge")
                if let ocr = clip.ocr, !ocr.isEmpty {
                    DisclosureGroup("Text in image", isExpanded: $showsImageText) {
                        Text(ocr)
                            .font(.system(size: 12.5))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
            }
        } else {
            Label("The screenshot file is missing", systemImage: "photo.badge.exclamationmark")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
        }
    }

    private static func fitted(_ size: NSSize, maxWidth: CGFloat, maxHeight: CGFloat) -> CGSize {
        guard size.width > 0, size.height > 0 else { return CGSize(width: maxWidth, height: maxHeight) }
        let scale = min(maxWidth / size.width, maxHeight / size.height, 1)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    /// App icon in its own spot, then the source and age, then a separate link to reopen it.
    private var sourceLine: some View {
        HStack(spacing: 8) {
            Label {
                Text("\(SourceLabel.short(clip.source)) · \(clip.created.formatted(.relative(presentation: .named)))")
                    .lineLimit(1)
            } icon: {
                Image(nsImage: AppIcons.icon(bundleID: clip.source.bundleID, appName: clip.source.app))
                    .resizable()
                    .frame(width: 14, height: 14)
            }
            .labelStyle(.titleAndIcon)
            if SourceOpener.canOpen(clip.source) {
                Text("·")
                Button(SourceOpener.label(clip.source)) { SourceOpener.open(clip.source) }
                    .buttonStyle(.link)
            }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.tertiary)
    }
}

private struct EnlargedImage: Identifiable {
    let image: NSImage
    var id: ObjectIdentifier { ObjectIdentifier(image) }
}

/// A screenshot at a readable size, with selectable text.
private struct EnlargedImageView: View {
    let image: NSImage
    let close: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            LiveTextImage(image: image)
                .aspectRatio(image.size, contentMode: .fit)
                .frame(maxWidth: 1000, maxHeight: 680)
            Button("Done", action: close).keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }
}
