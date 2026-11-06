import ClipbackCore
import SwiftUI

struct ClipDetailView: View {
    let stored: StoredClip
    let library: ClipLibrary

    @State private var confirmingDelete = false
    @State private var showsImageText = false
    @State private var titleDraft: String
    @State private var noteDraft: String
    @State private var newTag = ""
    @State private var isAddingTag = false
    @FocusState private var focus: Field?

    private enum Field { case title, note, tag }

    init(stored: StoredClip, library: ClipLibrary) {
        self.stored = stored
        self.library = library
        _titleDraft = State(initialValue: stored.clip.title)
        _noteDraft = State(initialValue: stored.clip.note)
    }

    private var clip: Clip { stored.clip }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                section("Your note") {
                    TextField("Add a note   @person   #tag", text: $noteDraft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .lineLimit(1...12)
                        .focused($focus, equals: .note)
                        .onSubmit(commitNote)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(focus == .note ? AnyShapeStyle(.background) : AnyShapeStyle(.quaternary.opacity(0.35)),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(focus == .note ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1))
                }
                if clip.kind == .text {
                    section(clip.before != nil || clip.after != nil ? "Highlight in context" : "Highlight") {
                        highlight
                    }
                    if let imageURL = stored.imageURL, let image = NSImage(contentsOf: imageURL) {
                        DisclosureGroup("Source window") {
                            screenshot(image).padding(.top, 6)
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    }
                } else {
                    section(clip.kind == .window ? "Window" : "Screenshot") {
                        if let imageURL = stored.imageURL, let image = NSImage(contentsOf: imageURL) {
                            screenshot(image)
                        } else {
                            Text("The image file is missing").foregroundStyle(.secondary)
                        }
                    }
                    if let ocr = clip.ocr, !ocr.isEmpty {
                        DisclosureGroup("Text in image", isExpanded: $showsImageText) {
                            Text(ocr)
                                .font(.system(size: 13))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 6)
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    }
                }
                section("Source") {
                    sourceCard
                    moreFromSource
                }
                footer
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: focus) { old, _ in
            if old == .title { commitTitle() }
            if old == .note { commitNote() }
        }
        .onDisappear {
            commitTitle()
            commitNote()
        }
        .confirmationDialog("Move this clip to the Trash?", isPresented: $confirmingDelete) {
            Button("Move to Trash", role: .destructive) { library.delete(stored) }
        } message: {
            Text("You can get it back from the Trash in Finder.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Untitled clip", text: $titleDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
                .focused($focus, equals: .title)
                .onSubmit { focus = nil }
                .help("Click to rename")
            HStack(spacing: 6) {
                Menu {
                    ForEach(Intent.allCases) { intent in
                        Button(intent.title) { setIntent(intent) }
                    }
                } label: {
                    HStack(spacing: 3) {
                        IntentPill(intent: clip.intent, people: clip.people, isDone: clip.done != nil)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Change what this clip is for")

                if clip.isArchived {
                    ArchivedBadge(date: clip.archivedOn)
                }
                ForEach(clip.tags, id: \.self) { tag in
                    TagChip(tag: tag) { removeTag(tag) }
                }
                if isAddingTag {
                    TextField("tag", text: $newTag)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5))
                        .frame(width: 90)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                        .focused($focus, equals: .tag)
                        .onSubmit(addTag)
                        .onExitCommand { isAddingTag = false; newTag = "" }
                        .onAppear { focus = .tag }
                } else {
                    Button {
                        isAddingTag = true
                    } label: {
                        Label("Tag", systemImage: "plus").font(.system(size: 11.5))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .help("Add a tag")
                }
                if clip.intent == .revise, let review = clip.review, !review.isRetired {
                    Text(review.daysUntilNext() < 1 ? "Due today" : "Next review \(review.whenNext())")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 4)
                }
            }
        }
    }

    /// With surrounding paragraphs: the selection highlighted inside them. Without: the selection as a quote.
    @ViewBuilder
    private var highlight: some View {
        if clip.before == nil && clip.after == nil {
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color.highlight).frame(width: 3)
                MarkdownText(text: clip.selection, size: 15, design: .serif, lineSpacing: 4)
                    .textSelection(.enabled)
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            highlightInContext
        }
    }

    private var highlightInContext: some View {
        var text = AttributedString(clip.before ?? "")
        var marked = AttributedString(clip.selection)
        marked.backgroundColor = Color.highlight
        marked.foregroundColor = .primary
        text.append(marked)
        text.append(AttributedString(clip.after ?? ""))
        return Text(text)
            .font(.system(size: 15, design: .serif))
            .lineSpacing(4)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func screenshot(_ image: NSImage) -> some View {
        LiveTextImage(image: image)
            .aspectRatio(image.size, contentMode: .fit)
            .frame(maxHeight: 520)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
    }

    private var sourceCard: some View {
        HStack(spacing: 12) {
            Image(nsImage: AppIcons.icon(bundleID: clip.source.bundleID, appName: clip.source.app))
                .resizable()
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(clip.source.app)
                Text(SourceOpener.detail(clip.source))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            if SourceOpener.canOpen(clip.source) {
                Button {
                    SourceOpener.open(clip.source)
                } label: {
                    Label(SourceOpener.label(clip.source), systemImage: "arrow.up.forward.square")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
    }

    /// A link to every clip from the same page or file, when there's more than this one.
    @ViewBuilder
    private var moreFromSource: some View {
        if let key = SourceKey.key(for: clip.source) {
            // The source list shows active clips, so the count and link only make sense for an active one.
            let count = library.activeClips.filter { SourceKey.key(for: $0.clip.source) == key }.count
            if !clip.isArchived, count > 1 {
                Button {
                    LibraryNavigation.shared.show(.source(key), selecting: stored.id)
                } label: {
                    Label("All \(count) clips from this \(clip.source.url != nil ? "page" : "file")", systemImage: "square.stack")
                }
                .buttonStyle(.link)
                .font(.system(size: 12.5))
                .padding(.top, 2)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Text("Captured \(clip.created.formatted(date: .abbreviated, time: .shortened))")
            Text("\(clip.library.title) library")
            if clip.isArchived {
                Button("Unarchive") { library.unarchive(ids: [stored.id]) }
                    .buttonStyle(.link)
            } else {
                Button("Archive") { library.archive(stored) }
                    .buttonStyle(.link)
            }
            Button("Move to \(otherLibrary.title)") { move() }
                .buttonStyle(.link)
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([stored.url]) }
                .buttonStyle(.link)
            Spacer()
            Button("Delete…") { confirmingDelete = true }
                .buttonStyle(.link)
                .foregroundStyle(.red)
        }
        .font(.system(size: 12))
        .foregroundStyle(.tertiary)
        .padding(.top, 4)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
            content()
        }
    }

    private var otherLibrary: Library { clip.library == .personal ? .work : .personal }

    private func commitTitle() {
        let title = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title != clip.title else { return }
        library.update(stored) { $0.title = title }
    }

    /// `@person` in the note sets who the clip is for, and `#tag` adds tags, just like in the capture panel.
    private func commitNote() {
        let note = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard note != clip.note else { return }
        library.update(stored) { clip in
            clip.note = note
            if let person = NoteParser.people(in: note).first { clip.person = person }
            for tag in NoteParser.tags(in: note) where !clip.tags.contains(tag) { clip.tags.append(tag) }
        }
    }

    private func addTag() {
        let tag = newTag.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .lowercased().replacingOccurrences(of: " ", with: "-")
        newTag = ""
        isAddingTag = false
        guard !tag.isEmpty, !clip.tags.contains(tag) else { return }
        library.update(stored) { $0.tags.append(tag) }
    }

    private func removeTag(_ tag: String) {
        library.update(stored) { $0.tags.removeAll { $0 == tag } }
    }

    private func move() {
        commitTitle()
        commitNote()
        let target = otherLibrary
        if library.move(stored, to: target) {
            Toast.shared.show("Moved to \(target.title)")
        }
    }

    private func setIntent(_ intent: Intent) {
        library.update(stored) { clip in
            clip.intent = intent
            if intent == .revise && clip.review == nil {
                clip.review = ReviewState.initial(after: Date())
            }
        }
    }
}

private struct TagChip: View {
    let tag: String
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 3) {
            Text("#\(tag)")
            if hovering {
                Button(action: remove) {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
                .help("Remove tag")
            }
        }
        .font(.system(size: 11.5))
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .foregroundStyle(.secondary)
        .background(.quaternary, in: Capsule())
        .onHover { hovering = $0 }
    }
}

/// Reopens where a clip came from: the page, the file, or at least the app.
@MainActor
enum SourceOpener {
    static func canOpen(_ source: ClipSource) -> Bool {
        source.url.flatMap(URL.init(string:)) != nil || source.file != nil || appURL(source) != nil
    }

    static func label(_ source: ClipSource) -> String {
        if source.url != nil { return "Open page" }
        if let file = source.file {
            return (file as NSString).pathExtension.isEmpty ? "Open folder" : "Open file"
        }
        return "Open \(source.app)"
    }

    static func detail(_ source: ClipSource) -> String {
        if let url = source.url { return url }
        if let file = source.file { return source.page.map { "\(file) · page \($0)" } ?? file }
        return source.window ?? source.app
    }

    static func open(_ source: ClipSource) {
        if let url = source.url.flatMap(URL.init(string:)) {
            NSWorkspace.shared.open(url)
        } else if let file = source.file {
            NSWorkspace.shared.open(URL(fileURLWithPath: file))
        } else if let app = appURL(source) {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private static func appURL(_ source: ClipSource) -> URL? {
        source.bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
    }
}
