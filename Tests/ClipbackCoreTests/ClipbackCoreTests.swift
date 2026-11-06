import Foundation
import Testing
@testable import ClipbackCore

private let ist = TimeZone(identifier: "Asia/Kolkata")!
// 2026-10-26 14:32:10 IST
private let created = Date(timeIntervalSince1970: 1_793_005_330)

@Suite struct NoteParserTests {
    @Test func findsPeopleAndTags() {
        let note = "ask @sam about pricing #launch #Pricing and @priya."
        #expect(NoteParser.people(in: note) == ["Sam", "Priya"])
        #expect(NoteParser.tags(in: note) == ["launch", "pricing"])
    }

    @Test func ignoresEmailsAndHashInsideWords() {
        #expect(NoteParser.tags(in: "issue c#sharp and url.com/#anchor") == [])
    }

    @Test func detectsTrailingTokenForAutocomplete() {
        #expect(NoteParser.trailingToken(in: "use for the talk @sa") == .init(sigil: "@", partial: "sa"))
        #expect(NoteParser.trailingToken(in: "#") == .init(sigil: "#", partial: ""))
        #expect(NoteParser.trailingToken(in: "@sam done") == nil)
    }

    @Test func clipPeopleIncludesEveryMention() {
        let clip = Clip(library: .work, intent: .call, person: "Maya", title: "t", source: ClipSource(app: "x"),
                        selection: "s", note: "standup @Maya @leo")
        #expect(clip.people == ["Maya", "Leo"])
    }

    @Test func stripsMentionsForDisplay() {
        #expect(NoteParser.withoutMentions("@AlexStone") == "")
        #expect(NoteParser.withoutMentions("ask @sam about #launch pricing") == "ask about pricing")
    }

    @Test func readableKeepsNamesDropsTags() {
        #expect(NoteParser.readable("pricing comparison for @Maya #launch") == "pricing comparison for Maya")
        #expect(NoteParser.readable("Q4 roadmap items left with @Priya") == "Q4 roadmap items left with Priya")
        #expect(NoteParser.readable("Discuss in standup tomorrow @Maya @Leo @Omar") == "Discuss in standup tomorrow")
        #expect(NoteParser.readable("check the onboarding step 3 copy @Leo") == "check the onboarding step 3 copy")
        #expect(NoteParser.readable("@Leo for the design review") == "Leo for the design review")
        #expect(NoteParser.readable("@AlexStone #launch") == "")
    }

    @Test func completesTrailingToken() {
        #expect(NoteParser.complete("ask @sa", with: "Sam") == "ask @Sam ")
        #expect(NoteParser.complete("#rea", with: "reading") == "#reading ")
    }
}

@Suite struct ClipMarkdownTests {
    private func clip(selection: String = "Spaced practice beats cramming, every time. Then the rest.") -> Clip {
        Clip(
            id: "01TEST",
            created: created,
            library: .personal,
            intent: .revise,
            person: nil,
            tags: ["learning", "memory"],
            title: ClipMarkdown.autoTitle(from: selection),
            source: ClipSource(app: "Google Chrome", bundleID: "com.google.Chrome", window: "Say \"hi\" – Blog", url: "https://example.com/a"),
            selection: selection,
            note: "revise before the exam @maya",
            before: "Before text. ",
            after: " After text.",
            review: ReviewState.initial(after: created, calendar: { var c = Calendar(identifier: .gregorian); c.timeZone = ist; return c }())
        )
    }

    @Test func pathUsesLocalTimeAndSlug() {
        #expect(ClipMarkdown.relativePath(for: clip(), timeZone: ist) == "2026/10/2026-10-26-1432-spaced-practice-beats-cramming-every-time.md")
    }

    @Test func rendersFrontMatterAndBody() {
        let text = ClipMarkdown.render(clip(), timeZone: ist)
        #expect(text.hasPrefix("---\nid: 01TEST\ncreated: 2026-10-26T14:32:10+05:30\n"))
        #expect(text.contains("tags: [\"learning\", \"memory\"]"))
        #expect(text.contains("  window: \"Say \\\"hi\\\" – Blog\""))
        #expect(text.contains("  page: null"))
        #expect(text.contains("review:\n  next: 2026-10-27\n  step: 0\n  status: active"))
        #expect(text.contains("\n> Spaced practice beats cramming, every time. Then the rest.\n"))
        #expect(text.contains("**Note:** revise before the exam @maya"))
        #expect(text.contains("Before text. ==Spaced practice beats cramming, every time. Then the rest.== After text."))
    }

    @Test func omitsEmptyNoteAndContext() {
        var c = clip()
        c.note = "  "
        c.before = nil
        c.after = nil
        let text = ClipMarkdown.render(c, timeZone: ist)
        #expect(!text.contains("**Note:**"))
        #expect(!text.contains("<details>"))
    }

    @Test func rendersImageClipWithOCR() {
        let clip = Clip(
            id: "01IMG",
            created: created,
            library: .personal,
            intent: .todo,
            title: "Caption overlaps the chart",
            source: ClipSource(app: "QuickTime Player"),
            kind: .region,
            image: "2026-10-26-1432-caption overlaps.png",
            ocr: "Compute doubled\nevery 6 months",
            selection: "",
            note: "move caption up"
        )
        let text = ClipMarkdown.render(clip, timeZone: ist)
        #expect(text.contains("kind: region\nimage: \"2026-10-26-1432-caption overlaps.png\""))
        #expect(text.contains("---\n\n![](2026-10-26-1432-caption%20overlaps.png)\n\n**Note:** move caption up"))
        #expect(text.contains("<details><summary>Text in image</summary>\n\nCompute doubled\nevery 6 months\n\n</details>"))
        #expect(!text.contains("\n> "))
    }

    @Test func autoTitleTakesFirstSentenceAndCutsLongOnes() {
        #expect(ClipMarkdown.autoTitle(from: "Short one. Second sentence.") == "Short one")
        let long = String(repeating: "word ", count: 30)
        let title = ClipMarkdown.autoTitle(from: long, maxLength: 20)
        #expect(title == "word word word word…")
    }

    @Test func imageTitleSkipsTimestampsAndFallsBackToWindow() {
        #expect(ClipMarkdown.imageTitle(ocr: "0:00 / 5:05", window: "Demo video – Draft 2", app: "Google Chrome") == "Demo video – Draft 2")
        #expect(ClipMarkdown.imageTitle(ocr: "+ 8\nRan a command, edited CLAUDE.md", window: "Claude", app: "Claude") == "Ran a command, edited CLAUDE.md")
        #expect(ClipMarkdown.imageTitle(ocr: nil, window: "Claude", app: "Claude") == "Screenshot from Claude")
    }

    @Test func slugIsAsciiAndShort() {
        #expect(ClipMarkdown.slug(for: "Café: What's next? (v2)") == "cafe-what-s-next-v2")
        #expect(ClipMarkdown.slug(for: "日本語") == "")
    }

    @Test func contextTrimKeepsWholeWords() {
        let (head, tail) = ClipMarkdown.trimContext(before: "rtial word here ", after: " next wor", wasCutBefore: true, wasCutAfter: true)
        #expect(head == "word here ")
        #expect(tail == " next")
    }
}

@Suite struct ClipParserTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = ist
        return c
    }

    @Test func textClipRoundTrips() {
        let original = Clip(
            id: "01RT",
            created: created,
            library: .work,
            intent: .revise,
            person: "Sam",
            tags: ["launch", "pricing, q4"],
            title: "Say \"hi\"\tthere",
            source: ClipSource(app: "Google Chrome", bundleID: "com.google.Chrome", window: "A – B", url: "https://x.y/z", file: nil, page: 4),
            image: "shot.png",
            selection: "Line one.\n\nLine three > with arrow",
            note: "ask @sam #launch",
            before: "Before. ",
            after: " After.",
            review: ReviewState.initial(after: created, calendar: calendar)
        )
        let parsed = ClipParser.parse(ClipMarkdown.render(original, timeZone: ist), calendar: calendar)
        #expect(parsed == original)
    }

    @Test func regionClipRoundTrips() {
        let original = Clip(
            id: "01RG", created: created, library: .personal, intent: .todo, title: "Caption overlaps",
            source: ClipSource(app: "QuickTime Player"), kind: .region, image: "a b.png",
            ocr: "Compute doubled\nevery 6 months", selection: "", note: "move it"
        )
        #expect(ClipParser.parse(ClipMarkdown.render(original, timeZone: ist), calendar: calendar) == original)
    }

    @Test func rejectsFilesWithoutFrontMatter() {
        #expect(ClipParser.parse("# just notes") == nil)
    }
}

@Suite struct ReviewTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = ist
        return c
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: created))!
    }

    @Test func gotItWalksTheIntervalsThenRepeatsTheLast() {
        var state = ReviewState(next: day(0))
        var gaps: [Int] = []
        for _ in 0..<7 {
            state = ReviewScheduler.apply(.gotIt, to: state, today: day(0), calendar: calendar)
            gaps.append(calendar.dateComponents([.day], from: day(0), to: state.next).day!)
        }
        #expect(gaps == [3, 7, 16, 35, 75, 75, 75])
        #expect(state.last == day(0))
    }

    @Test func againResetsAndRetireStops() {
        let later = ReviewState(next: day(5), step: 3)
        let again = ReviewScheduler.apply(.again, to: later, today: day(5), calendar: calendar)
        #expect(again.step == 0 && again.next == day(6))
        #expect(ReviewScheduler.apply(.retire, to: later, today: day(5), calendar: calendar).isRetired)
    }

    @Test func todayCapsAtFiveIncludingAlreadyReviewed() {
        func clip(_ id: String, next: Int, last: Int? = nil, intent: Intent = .revise) -> Clip {
            Clip(id: id, created: day(-10), library: .personal, intent: intent, title: id, source: ClipSource(app: "x"),
                 selection: id, review: ReviewState(next: day(next), last: last.map(day)))
        }
        let clips = [
            clip("a", next: -3), clip("b", next: 0), clip("c", next: -1), clip("d", next: 0), clip("e", next: 0),
            clip("f", next: 0), clip("future", next: 2), clip("done", next: 3, last: 0), clip("save", next: 0, intent: .save),
        ]
        let today = ReviewQueue.today(clips, clip: { $0 }, now: day(0).addingTimeInterval(3600), calendar: calendar)
        #expect(today.reviewedToday == 1)
        #expect(today.due.map(\.id) == ["a", "c", "b", "d"])
        #expect(today.total == 5)
    }

    @Test func doneAndLastRoundTrip() {
        let clip = Clip(id: "01D", created: created, library: .work, intent: .todo, title: "t", source: ClipSource(app: "x"),
                        selection: "s", review: ReviewState(next: day(3), step: 2, last: day(0)), done: day(0))
        #expect(ClipParser.parse(ClipMarkdown.render(clip, timeZone: ist), calendar: calendar) == clip)
    }

    @Test func agendaListsNotesWithShortQuotes() {
        let clips = [
            Clip(library: .work, intent: .call, person: "Sam", title: "Pricing", source: ClipSource(app: "Granola"),
                 selection: "Two pricing options\nby Friday", note: "check margin"),
            Clip(library: .work, intent: .call, person: "Sam", title: "Partner list", source: ClipSource(app: "Chrome"),
                 selection: "Three partners"),
        ]
        let text = Agenda.markdown(person: "Sam", clips: clips, date: created, timeZone: ist)
        #expect(text == "## Sam · 26 Oct\n\n1. check margin\n   > Two pricing options by Friday\n2. Partner list\n   > Three partners\n")
    }
}

@Suite struct SourceKeyTests {
    @Test func samePageMatchesDespiteTrackingAndFragments() {
        let a = SourceKey.key(for: ClipSource(app: "Chrome", url: "https://www.Example.com/post/?utm_source=x#intro"))
        let b = SourceKey.key(for: ClipSource(app: "Safari", url: "https://example.com/post"))
        #expect(a == b)
        #expect(a == "url:https://example.com/post")
    }

    @Test func meaningfulQueryKeepsPagesApart() {
        let one = SourceKey.key(for: ClipSource(app: "Chrome", url: "http://localhost:3000/player.html?v=a.mp4"))
        let two = SourceKey.key(for: ClipSource(app: "Chrome", url: "http://localhost:3000/player.html?v=b.mp4"))
        #expect(one != two)
    }

    @Test func filesByPathAndAppOnlyHasNoKey() {
        #expect(SourceKey.key(for: ClipSource(app: "Preview", file: "/a/b.pdf", page: 3)) == "file:/a/b.pdf")
        #expect(SourceKey.key(for: ClipSource(app: "Claude", window: "Claude")) == nil)
    }
}

@Suite struct MarkdownBlocksTests {
    @Test func parsesGranolaStyleNotes() {
        let text = "# Planning and Next Steps\n\n- Leo to review the branch\n  - keep reusable parts\n\n\n1. Omar rejoins\nPlain line"
        #expect(MarkdownBlocks.parse(text) == [
            .heading(level: 1, text: "Planning and Next Steps"),
            .gap,
            .bullet(indent: 0, text: "Leo to review the branch"),
            .bullet(indent: 1, text: "keep reusable parts"),
            .gap,
            .numbered(indent: 0, marker: "1.", text: "Omar rejoins"),
            .paragraph("Plain line"),
        ])
        #expect(MarkdownBlocks.hasStructure(text))
        #expect(!MarkdownBlocks.hasStructure("Just a sentence.\nAnd another, with #hashtag."))
    }
}

@Suite struct ClipSearchTests {
    @Test func everyWordMustMatchAnywhere() {
        let clip = Clip(library: .work, intent: .call, person: "Sam", tags: ["launch"], title: "Pricing options",
                        source: ClipSource(app: "Granola"), selection: "Two options for the launch", note: "check margin")
        #expect(ClipSearch.matches(clip, query: "pricing MARGIN"))
        #expect(ClipSearch.matches(clip, query: "@sam #launch"))
        #expect(ClipSearch.matches(clip, query: "granola"))
        #expect(!ClipSearch.matches(clip, query: "pricing slack"))
        #expect(ClipSearch.matches(clip, query: "  "))
    }
}

@Suite struct LibraryGuesserTests {
    @Test func workAppsAndKeywordsGoToWork() {
        let guesser = LibraryGuesser(workRules: [" Slack", "acme.com", "com.granola.app", ""])
        #expect(guesser.guess(for: ClipSource(app: "Slack", bundleID: "com.tinyspeck.slackmacgap"), fallback: .personal) == .work)
        #expect(guesser.guess(for: ClipSource(app: "Granola", bundleID: "com.granola.app"), fallback: .personal) == .work)
        #expect(guesser.guess(for: ClipSource(app: "Chrome", window: "Inbox - sam@ACME.com"), fallback: .personal) == .work)
        #expect(guesser.guess(for: ClipSource(app: "Terminal", window: "~/Downloads/Resume"), fallback: .personal) == .personal)
        #expect(guesser.guess(for: ClipSource(app: "Terminal"), fallback: .work) == .work)
    }

    @Test func noRulesMeansTheFallback() {
        let guesser = LibraryGuesser(workRules: [])
        #expect(guesser.guess(for: ClipSource(app: "Slack", bundleID: "com.tinyspeck.slackmacgap"), fallback: .personal) == .personal)
    }
}

@Suite struct PeopleDirectoryTests {
    @Test func usesFirstNamesUnlessShared() {
        let handles = PeopleDirectory.handles(for: ["Dana Kim", "Alex Stone", "Alex Sutton", "Sam", "jordan lee"])
        #expect(handles == ["Dana", "AlexStone", "AlexSutton", "Sam", "Jordan"])
    }

    @Test func matchesHandleThenAnyNamePart() {
        let people = [
            Person(handle: "AlexStone", name: "Alex Stone"),
            Person(handle: "Dana", name: "Dana Kim"),
            Person(handle: "Sid", name: "Sid Bauer"),
        ]
        #expect(PeopleDirectory.matches("ale", in: people).map(\.handle) == ["AlexStone"])
        #expect(PeopleDirectory.matches("sto", in: people).map(\.handle) == ["AlexStone"])
        #expect(PeopleDirectory.matches("s", in: people).map(\.handle) == ["Sid", "AlexStone"])
        #expect(PeopleDirectory.matches("zed", in: people).isEmpty)
    }
}

@Suite struct TextCleanerTests {
    @Test func removesInvisiblesAndNormalisesLineEnds() {
        #expect(TextCleaner.clean("  stopped)\u{FFFC}\r\nnext\u{200B}\u{00A0}line \n") == "stopped)\nnext line")
    }
}

@Suite struct WorkHoursTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = ist
        return c
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func weekdayOfficeHoursAreWork() {
        let hours = WorkHours.standard
        // 28 Oct 2026 is a Wednesday, 31 Oct a Saturday.
        #expect(hours.library(at: at(28, 10, 0), calendar: calendar) == .work)
        #expect(hours.library(at: at(28, 17, 59), calendar: calendar) == .work)
        #expect(hours.library(at: at(28, 9, 59), calendar: calendar) == .personal)
        #expect(hours.library(at: at(28, 18, 0), calendar: calendar) == .personal)
        #expect(hours.library(at: at(31, 12, 0), calendar: calendar) == .personal)
        #expect(hours.summary == "Mon–Fri 10:00–18:00")
    }
}

@Suite struct ReviewDayTests {
    private let calendar = Calendar(identifier: .gregorian)

    @Test func countsCalendarDaysNotHours() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 3))!
        func state(_ day: Int) -> ReviewState {
            ReviewState(next: calendar.date(from: DateComponents(year: 2026, month: 11, day: day))!)
        }
        #expect(state(5).whenNext(from: now, calendar: calendar) == "today")
        #expect(state(3).whenNext(from: now, calendar: calendar) == "today")
        #expect(state(6).whenNext(from: now, calendar: calendar) == "tomorrow")
        #expect(state(12).whenNext(from: now, calendar: calendar) == "in 7 days")
        #expect(state(3).daysUntilNext(from: now, calendar: calendar) == -2)
    }
}

@Suite struct ArchiveTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = ist
        return c
    }

    private func clip(intent: Intent = .save) -> Clip {
        Clip(id: "01A", created: created, library: .work, intent: intent, title: "t", source: ClipSource(app: "x"), selection: "s")
    }

    @Test func finishedClipsCountAsArchived() {
        var discussed = clip(intent: .call)
        discussed.done = created
        var retired = clip(intent: .revise)
        retired.review = ReviewState(next: created, isRetired: true, last: created)
        var putAway = clip()
        putAway.archived = created
        #expect(discussed.isArchived && retired.isArchived && putAway.isArchived)
        #expect(!clip().isArchived)
    }

    @Test func unarchiveMakesItActiveAgain() {
        var retired = clip(intent: .revise)
        retired.review = ReviewState(next: created, step: 3, isRetired: true, last: created)
        retired.done = created
        retired.archived = created
        retired.unarchive(today: created, calendar: calendar)
        #expect(!retired.isArchived)
        #expect(retired.review?.next == calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: created)))
    }

    @Test func archivedRoundTrips() {
        var c = clip()
        c.archived = calendar.startOfDay(for: created)
        #expect(ClipParser.parse(ClipMarkdown.render(c, timeZone: ist), calendar: calendar) == c)
    }
}

@Suite struct ULIDTests {
    @Test func isSortableAndWellFormed() {
        let a = ULID.make(date: Date(timeIntervalSince1970: 1_000))
        let b = ULID.make(date: Date(timeIntervalSince1970: 2_000))
        #expect(a.count == 26)
        #expect(a < b)
    }
}
