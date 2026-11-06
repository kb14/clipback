import AppKit
import ClipbackCore
import Observation

/// The clip being edited in the capture panel, before it's saved.
@MainActor
@Observable
final class CaptureDraft {
    let context: GrabbedContext
    let selection: String
    let kind: ClipKind
    /// The picked region or window, or for text clips a screenshot of the window the text came from.
    let image: CGImage?
    private(set) var ocrText: String?
    private(set) var isReadingText = false

    var note = "" {
        didSet { noteDidChange() }
    }
    var intent: Intent = .save
    var library: Library {
        didSet { peoplePool = PeopleStore.autocompletePool(for: library, recentHandles: recentPeople) }
    }
    private(set) var suggestions: [Suggestion] = []
    var highlightedSuggestion = 0

    struct Suggestion: Equatable {
        /// Inserted after the `@` or `#`.
        var value: String
        /// Full name and title, shown beside a person.
        var detail: String?
    }

    @ObservationIgnored private let recentPeople: [String]
    @ObservationIgnored private let knownTags: [String]
    @ObservationIgnored private var peoplePool: [Person]
    @ObservationIgnored private var suggestionsDismissed = false
    @ObservationIgnored private var ocrTask: Task<Void, Never>?

    init(context: GrabbedContext, selection: String, kind: ClipKind = .text, image: CGImage? = nil,
         library: Library, recentPeople: [String], knownTags: [String]) {
        self.context = context
        self.selection = selection
        self.kind = kind
        self.image = image
        self.library = library
        self.recentPeople = recentPeople
        self.knownTags = knownTags
        peoplePool = PeopleStore.autocompletePool(for: library, recentHandles: recentPeople)
        startReadingText()
    }

    /// Image clips are read in the background while the panel is open; saving waits for it.
    func waitForText() async {
        await ocrTask?.value
    }

    private func startReadingText() {
        guard kind != .text, let image else { return }
        isReadingText = true
        ocrTask = Task {
            let text = await OCR.text(in: image)
            ocrText = TextCleaner.clean(text)
            isReadingText = false
        }
    }

    var people: [String] { NoteParser.people(in: note) }
    var tags: [String] { NoteParser.tags(in: note) }

    /// One line naming the source: page title and site, file and page, or window title.
    var sourceLine: String {
        let source = context.source
        let title = source.window.map(Self.stripBrowserSuffix)
        if let url = source.url, let host = URL(string: url)?.host() {
            return [title, host.replacingOccurrences(of: "www.", with: "")].compactMap { $0 }.joined(separator: " · ")
        }
        if let file = source.file {
            let name = (file as NSString).lastPathComponent
            return source.page.map { "\(name) · page \($0)" } ?? name
        }
        return [source.app, title].compactMap { $0 }.joined(separator: " · ")
    }

    func toggleLibrary() {
        library = library == .personal ? .work : .personal
    }

    func selectIntent(number: Int) {
        guard Intent.allCases.indices.contains(number - 1) else { return }
        intent = Intent.allCases[number - 1]
    }

    /// Returns false when there was no suggestion to accept.
    func acceptSuggestion() -> Bool {
        guard suggestions.indices.contains(highlightedSuggestion) else { return false }
        note = NoteParser.complete(note, with: suggestions[highlightedSuggestion].value)
        return true
    }

    func moveHighlight(by step: Int) {
        guard !suggestions.isEmpty else { return }
        highlightedSuggestion = (highlightedSuggestion + step + suggestions.count) % suggestions.count
    }

    func dismissSuggestions() {
        suggestionsDismissed = true
        suggestions = []
    }

    func makeClip(at date: Date = Date()) -> Clip {
        Clip(
            created: date,
            library: library,
            intent: intent,
            person: people.first,
            tags: tags,
            title: title,
            source: context.source,
            kind: kind,
            ocr: ocrText,
            selection: selection,
            note: note,
            before: context.before,
            after: context.after,
            review: intent == .revise ? ReviewState.initial(after: date) : nil
        )
    }

    private var title: String {
        if kind == .text { return ClipMarkdown.autoTitle(from: selection) }
        let window = context.source.window.map(Self.stripBrowserSuffix)
        return ClipMarkdown.imageTitle(ocr: ocrText, window: window, app: context.source.app)
    }

    private func noteDidChange() {
        if !people.isEmpty, intent == .save { intent = .call }
        suggestionsDismissed = false
        refreshSuggestions()
    }

    private func refreshSuggestions() {
        guard !suggestionsDismissed, let token = NoteParser.trailingToken(in: note) else {
            suggestions = []
            return
        }
        if token.sigil == "@" {
            suggestions = PeopleDirectory.matches(token.partial, in: peoplePool).map { person in
                let detail = [person.name == person.handle ? nil : person.name, person.title].compactMap { $0 }.joined(separator: " · ")
                return Suggestion(value: person.handle, detail: detail.isEmpty ? nil : detail)
            }
        } else {
            let partial = token.partial.lowercased()
            suggestions = knownTags
                .filter { $0.lowercased().hasPrefix(partial) && $0.lowercased() != partial }
                .prefix(4)
                .map { Suggestion(value: $0) }
        }
        highlightedSuggestion = 0
    }

    private static func stripBrowserSuffix(_ title: String) -> String {
        title.replacing(#/ [-–] (Google Chrome|Brave|Microsoft Edge|Arc)( [-–] .*)?$/#, with: "")
    }
}
