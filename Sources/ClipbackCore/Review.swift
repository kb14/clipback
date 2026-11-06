import Foundation

/// How a Revise clip is answered in Today.
public enum ReviewAnswer: Sendable {
    /// Remembered it: wait longer before showing it again.
    case gotIt
    /// Didn't remember: start over from tomorrow.
    case again
    /// Never show it again.
    case retire
}

public enum ReviewScheduler {
    /// Days until the next showing after each "Got it": 1, 3, 7, 16, 35, then every 75.
    public static func apply(_ answer: ReviewAnswer, to state: ReviewState, today: Date, calendar: Calendar = .current) -> ReviewState {
        let start = calendar.startOfDay(for: today)
        var next = state
        next.last = start
        switch answer {
        case .gotIt:
            next.step = min(state.step + 1, ReviewState.intervals.count - 1)
            next.next = calendar.date(byAdding: .day, value: ReviewState.intervals[next.step], to: start) ?? start
        case .again:
            next.step = 0
            next.next = calendar.date(byAdding: .day, value: ReviewState.intervals[0], to: start) ?? start
        case .retire:
            next.isRetired = true
        }
        return next
    }

    /// Days until the clip returns if answered "Got it" now, for the button label.
    public static func daysAfterGotIt(_ state: ReviewState) -> Int {
        ReviewState.intervals[min(state.step + 1, ReviewState.intervals.count - 1)]
    }
}

extension ReviewState {
    /// Whole calendar days until the clip comes back; 0 or less means it's due now. Review dates are days, so
    /// measuring from the clock would say "3 hours ago" for a clip due today.
    public func daysUntilNext(from now: Date = Date(), calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: next)).day ?? 0
    }

    /// "today", "tomorrow" or "in 3 days".
    public func whenNext(from now: Date = Date(), calendar: Calendar = .current) -> String {
        switch daysUntilNext(from: now, calendar: calendar) {
        case ..<1: "today"
        case 1: "tomorrow"
        case let days: "in \(days) days"
        }
    }
}

/// Which Revise clips Today shows. At most `dailyLimit` a day, counting ones already reviewed today,
/// oldest due first so nothing starves.
public enum ReviewQueue {
    public static let dailyLimit = 5

    public struct Today<Item>: Sendable where Item: Sendable {
        public var due: [Item]
        public var reviewedToday: Int
        public var total: Int { due.count + reviewedToday }
    }

    public static func today<Item: Sendable>(_ items: [Item], clip: (Item) -> Clip, now: Date, calendar: Calendar = .current,
                                             limit: Int = dailyLimit) -> Today<Item> {
        let start = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: start) ?? now
        let revise = items.filter { clip($0).intent == .revise && clip($0).review?.isRetired != true }
        let reviewedToday = revise.filter { clip($0).review?.last.map { calendar.isDate($0, inSameDayAs: now) } ?? false }.count
        let due = revise
            .filter { item in
                guard let review = clip(item).review else { return true }
                return review.next < tomorrow && !(review.last.map { calendar.isDate($0, inSameDayAs: now) } ?? false)
            }
            .sorted { (clip($0).review?.next ?? clip($0).created) < (clip($1).review?.next ?? clip($1).created) }
        return Today(due: Array(due.prefix(max(0, limit - reviewedToday))), reviewedToday: reviewedToday)
    }
}

/// A person's open Call items as markdown, ready to paste before the call.
public enum Agenda {
    public static func markdown(person: String, clips: [Clip], date: Date, timeZone: TimeZone = .current) -> String {
        let day = date.formatted(Date.FormatStyle(timeZone: timeZone).day().month(.abbreviated))
        var lines = ["## \(person) · \(day)", ""]
        for (index, clip) in clips.enumerated() {
            let note = NoteParser.readable(clip.note)
            lines.append("\(index + 1). \(note.isEmpty ? clip.title : note)")
            let quote = (clip.kind == .text ? clip.selection : clip.ocr ?? "")
                .split(whereSeparator: \.isNewline).joined(separator: " ")
            if !quote.isEmpty {
                lines.append("   > \(quote.count > 220 ? String(quote.prefix(220)) + "…" : quote)")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
