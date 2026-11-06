import Foundation

public enum Library: String, CaseIterable, Identifiable, Sendable {
    case personal
    case work

    public var id: String { rawValue }
    public var title: String { self == .personal ? "Personal" : "Work" }
}

/// What a clip should turn into later.
public enum Intent: String, CaseIterable, Identifiable, Sendable {
    case save
    case revise
    case call
    case todo

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .save: "Save"
        case .revise: "Revise"
        case .call: "Call"
        case .todo: "To-do"
        }
    }
}

public enum ClipKind: String, Sendable {
    case text
    case region
    case window
}

/// Where a clip came from, captured at the moment the hotkey was pressed.
public struct ClipSource: Sendable, Equatable {
    public var app: String
    public var bundleID: String?
    public var window: String?
    public var url: String?
    public var file: String?
    public var page: Int?

    public init(app: String, bundleID: String? = nil, window: String? = nil, url: String? = nil, file: String? = nil, page: Int? = nil) {
        self.app = app
        self.bundleID = bundleID
        self.window = window
        self.url = url
        self.file = file
        self.page = page
    }
}

/// Spaced revision state for Revise clips.
public struct ReviewState: Sendable, Equatable {
    public static let intervals = [1, 3, 7, 16, 35, 75]

    public var next: Date
    public var step: Int
    public var isRetired: Bool
    /// The day it was last reviewed, so Today can count what you've already done.
    public var last: Date?

    public init(next: Date, step: Int = 0, isRetired: Bool = false, last: Date? = nil) {
        self.next = next
        self.step = step
        self.isRetired = isRetired
        self.last = last
    }

    /// A new Revise clip comes back the next day.
    public static func initial(after created: Date, calendar: Calendar = .current) -> ReviewState {
        let start = calendar.startOfDay(for: created)
        return ReviewState(next: calendar.date(byAdding: .day, value: intervals[0], to: start) ?? created)
    }
}

public struct Clip: Sendable, Equatable {
    public var id: String
    public var created: Date
    public var library: Library
    public var intent: Intent
    public var person: String?
    public var tags: [String]
    public var title: String
    public var source: ClipSource
    public var kind: ClipKind
    public var image: String?
    /// Text read from the image of a region or window clip.
    public var ocr: String?
    public var selection: String
    public var note: String
    public var before: String?
    public var after: String?
    public var review: ReviewState?
    /// When a Call item was discussed or a To-do was finished.
    public var done: Date?
    /// When the clip was put away by hand.
    public var archived: Date?

    /// Finished with: put away by hand, discussed or done, or retired from revision. Archived clips leave
    /// Inbox, Calls, To-do and review, but stay in their file and in search.
    public var isArchived: Bool {
        archived != nil || done != nil || review?.isRetired == true
    }

    /// When it became archived, for ordering the Archive view.
    public var archivedOn: Date? {
        archived ?? done ?? (review?.isRetired == true ? review?.last : nil)
    }

    /// Back to fully active: off the archive, not done, and back in revision from tomorrow if it was retired.
    public mutating func unarchive(today: Date = Date(), calendar: Calendar = .current) {
        archived = nil
        done = nil
        if var state = review, state.isRetired {
            state.isRetired = false
            state.next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today)) ?? today
            review = state
        }
    }

    public init(
        id: String = ULID.make(),
        created: Date = Date(),
        library: Library,
        intent: Intent,
        person: String? = nil,
        tags: [String] = [],
        title: String,
        source: ClipSource,
        kind: ClipKind = .text,
        image: String? = nil,
        ocr: String? = nil,
        selection: String,
        note: String = "",
        before: String? = nil,
        after: String? = nil,
        review: ReviewState? = nil,
        done: Date? = nil,
        archived: Date? = nil
    ) {
        self.id = id
        self.created = created
        self.library = library
        self.intent = intent
        self.person = person
        self.tags = tags
        self.title = title
        self.source = source
        self.kind = kind
        self.image = image
        self.ocr = ocr
        self.selection = selection
        self.note = note
        self.before = before
        self.after = after
        self.review = review
        self.done = done
        self.archived = archived
    }
}
