#if DEBUG
import AppKit
import ClipbackCore

/// Made-up clips that look like a few days of real use, for the README screenshots. Unlike `Fixtures`, which covers
/// awkward cases, these are ordinary ones. People and companies are invented; quotes come from public-domain books
/// and Wikipedia. Written into a throwaway vault only.
enum Showcase {
    static func write(into vault: URL) throws {
        try Fixtures.clearThrowaway(vault)
        let fileManager = FileManager.default
        let work = vault.appending(path: "Work/2026/11")
        let personal = vault.appending(path: "Personal/2026/11")
        try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: personal, withIntermediateDirectories: true)

        let people = [
            Person(handle: "Maya", name: "Maya Chen"), Person(handle: "Leo", name: "Leo Park"),
            Person(handle: "Priya", name: "Priya Nair"), Person(handle: "Sam", name: "Sam Rivera"),
        ]
        try JSONEncoder().encode(people).write(to: vault.appending(path: "Work/people.json"))

        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today) ?? today }

        func save(_ clip: Clip, minutesAgo: Int, in folder: URL, name: String, image: NSImage? = nil) throws {
            var clip = clip
            clip.created = now.addingTimeInterval(TimeInterval(-60 * minutesAgo))
            if let image {
                clip.image = "\(name).png"
                try Fixtures.png(image).write(to: folder.appending(path: "\(name).png"))
            }
            try Data(ClipMarkdown.render(clip).utf8).write(to: folder.appending(path: "\(name).md"))
        }

        // Personal: reading, a book, family errands.
        try save(Clip(library: .personal, intent: .revise, tags: ["learning"], title: "Spacing beats cramming",
                      source: ClipSource(app: "Safari", bundleID: "com.apple.Safari", window: "Spacing effect - Wikipedia",
                                         url: "https://en.wikipedia.org/wiki/Spacing_effect"),
                      selection: "The spacing effect demonstrates that learning is more effective when study sessions are spaced out.",
                      note: "Spanish: ten minutes a day, not two hours on Sunday",
                      before: nil,
                      after: " This effect shows that more information is encoded into long-term memory by spaced study sessions, also known as spaced repetition or spaced presentation, than by massed presentation (\"cramming\").",
                      review: ReviewState(next: day(2), step: 1, last: day(-1))),
                 minutesAgo: 35, in: personal, name: "wikipedia-spacing")

        try save(Clip(library: .personal, intent: .revise, tags: ["reading"], title: "Frittered away by detail",
                      source: ClipSource(app: "Books", bundleID: "com.apple.iBooksX", window: "Walden"),
                      selection: "Our life is frittered away by detail. An honest man has hardly need to count more than his ten fingers, or in extreme cases he may add his ten toes, and lump the rest. Simplicity, simplicity, simplicity!",
                      note: "", review: ReviewState(next: day(-1), step: 2, last: day(-8))),
                 minutesAgo: 60 * 24 * 9, in: personal, name: "books-walden")

        try save(Clip(library: .personal, intent: .revise, tags: ["reading"], title: "Live deliberately",
                      source: ClipSource(app: "Books", bundleID: "com.apple.iBooksX", window: "Walden"),
                      selection: "I went to the woods because I wished to live deliberately, to front only the essential facts of life, and see if I could not learn what it had to teach, and not, when I came to die, discover that I had not lived.",
                      note: "", review: ReviewState(next: day(0), step: 3, last: day(-16))),
                 minutesAgo: 60 * 24 * 30, in: personal, name: "books-deliberately")

        try save(Clip(library: .personal, intent: .revise, tags: ["learning"], title: "The forgetting curve",
                      source: ClipSource(app: "Safari", bundleID: "com.apple.Safari", window: "Forgetting curve - Wikipedia",
                                         url: "https://en.wikipedia.org/wiki/Forgetting_curve"),
                      kind: .region, ocr: "Memory retained\n100%\n50%\nDays since learning\n1 2 3 4 5 6 7",
                      selection: "", note: "each review flattens it",
                      review: ReviewState(next: day(3), step: 1, last: day(0))),
                 minutesAgo: 60 * 26, in: personal, name: "forgetting-curve", image: forgettingCurve())

        try save(Clip(library: .personal, intent: .todo, title: "Car insurance renews on the 20th",
                      source: ClipSource(app: "WhatsApp", bundleID: "net.whatsapp.WhatsApp", window: "Dad"),
                      selection: "Car insurance renews on the 20th. They need the new registration copy before that, the old one has the wrong address.",
                      note: "scan the registration this weekend"),
                 minutesAgo: 95, in: personal, name: "whatsapp-insurance")

        try save(Clip(library: .personal, intent: .save, tags: ["food"], title: "Ask for the kokum sherbet",
                      source: ClipSource(app: "Messages", bundleID: "com.apple.MobileSMS", window: "Ana"),
                      selection: "Go to the one near the station, not the mall. Ask for the kokum sherbet, it's not on the menu.",
                      note: "for when Ravi visits"),
                 minutesAgo: 60 * 28, in: personal, name: "messages-restaurant")

        try save(Clip(library: .personal, intent: .save, tags: ["gifts"], title: "Dotted notebook, A5",
                      source: ClipSource(app: "Notes", bundleID: "com.apple.Notes", window: "Gift ideas"),
                      selection: "Mum: the A5 notebook with dotted pages, not lined. She said the lined ones feel like school.",
                      note: ""),
                 minutesAgo: 60 * 50, in: personal, name: "notes-gift")

        // Work: a small product team at a made-up company.
        try save(Clip(library: .work, intent: .call, person: "Priya", title: "Can we move the beta to the 14th?",
                      source: ClipSource(app: "Slack", bundleID: "com.tinyspeck.slackmacgap", window: "#desktop-beta - Slack"),
                      selection: "Can we move the beta to the 14th? QA found two crashes on macOS 14 and I'd rather fix them than ship a known bug.",
                      note: "check with @Priya before the marketing email goes out"),
                 minutesAgo: 40, in: work, name: "slack-beta-date")

        try save(Clip(library: .work, intent: .call, person: "Leo", title: "What would make you use it daily?",
                      source: ClipSource(app: "Preview", bundleID: "com.apple.Preview", window: "Customer survey Q3.pdf – Page 12 of 18",
                                         file: "/Users/example/Downloads/Customer survey Q3.pdf", page: 12),
                      kind: .region,
                      ocr: "What would make you use it daily?\nWorks offline 41%\nFaster search 27%\nMobile app 19%\nExport to PDF 13%",
                      selection: "", note: "offline keeps coming up. worth scoping for Q1? @Leo"),
                 minutesAgo: 130, in: work, name: "preview-survey", image: surveyChart())

        try save(Clip(library: .work, intent: .call, person: "Leo", title: "Backoff with jitter",
                      source: ClipSource(app: "Claude", bundleID: "com.anthropic.claudefordesktop", window: "Claude"),
                      selection: """
                      Retry failed sync requests with exponential backoff: wait 1s, 2s, 4s, up to a cap of 60s. Add random jitter to each wait so a thousand clients that went offline together don't all retry in the same second.
                      """,
                      note: "is this what we want for the sync client? @Leo"),
                 minutesAgo: 60 * 22, in: work, name: "claude-backoff")

        try save(Clip(library: .work, intent: .call, person: "Leo", title: "Sidebar keeps the old colours",
                      source: ClipSource(app: "Google Chrome", bundleID: "com.google.Chrome", window: "Sidebar keeps old colours · Issue #482",
                                         url: "https://github.com/northwind-apps/desktop/issues/482"),
                      selection: "Open Settings, switch to Dark, close and reopen the window. The sidebar keeps the light colours until you resize it.",
                      note: "same bug as the toolbar one? @Leo"),
                 minutesAgo: 60 * 27, in: work, name: "github-issue")

        try save(Clip(library: .work, intent: .todo, title: "Onboarding review: next steps",
                      source: ClipSource(app: "Granola", bundleID: "com.granola.app", window: "Onboarding review"),
                      selection: """
                      ### Next steps
                      - Maya to shorten step 3 to one sentence
                      - Leo to remove the email field from step 2
                      - Send the new copy to Sam for the help centre by Thursday
                      """,
                      note: "my part: the help centre copy"),
                 minutesAgo: 60 * 4, in: work, name: "granola-onboarding")

        try save(Clip(library: .work, intent: .todo, title: "Sign the renewal by Friday",
                      source: ClipSource(app: "Mail", bundleID: "com.apple.mail", window: "Re: Renewal for 2027"),
                      selection: "Could you sign and return the renewal by Friday? The current agreement ends on the 30th.",
                      note: ""),
                 minutesAgo: 60 * 49, in: work, name: "mail-renewal")
    }

    /// A slide from a survey PDF: one bar chart.
    private static func surveyChart() -> NSImage {
        Fixtures.draw(NSSize(width: 1280, height: 720)) { rect in
            NSColor.white.setFill()
            rect.fill()
            Fixtures.text("What would make you use it daily?", at: NSPoint(x: 80, y: 64), size: 44, weight: .bold, color: NSColor(white: 0.1, alpha: 1))
            Fixtures.text("312 responses, September", at: NSPoint(x: 80, y: 130), size: 24, color: .gray)
            let rows: [(String, CGFloat)] = [("Works offline", 41), ("Faster search", 27), ("Mobile app", 19), ("Export to PDF", 13)]
            for (index, row) in rows.enumerated() {
                let y = 220 + CGFloat(index) * 110
                Fixtures.text(row.0, at: NSPoint(x: 80, y: y + 18), size: 28, color: NSColor(white: 0.15, alpha: 1))
                let bar = NSRect(x: 340, y: y, width: row.1 * 18, height: 70)
                (index == 0 ? NSColor.systemIndigo : NSColor(white: 0.78, alpha: 1)).setFill()
                NSBezierPath(roundedRect: bar, xRadius: 6, yRadius: 6).fill()
                Fixtures.text("\(Int(row.1))%", at: NSPoint(x: bar.maxX + 18, y: y + 16), size: 30, weight: .semibold, color: NSColor(white: 0.15, alpha: 1))
            }
        }
    }

    /// A chart of memory over time, as on the Wikipedia page.
    static func forgettingCurve() -> NSImage {
        Fixtures.draw(NSSize(width: 900, height: 520)) { rect in
            NSColor.white.setFill()
            rect.fill()
            let origin = NSPoint(x: 110, y: 430)
            let axes = NSBezierPath()
            axes.move(to: NSPoint(x: origin.x, y: 50))
            axes.line(to: origin)
            axes.line(to: NSPoint(x: 840, y: origin.y))
            NSColor(white: 0.3, alpha: 1).setStroke()
            axes.lineWidth = 2
            axes.stroke()
            Fixtures.text("Memory retained", at: NSPoint(x: 110, y: 14), size: 20, weight: .medium, color: .darkGray)
            Fixtures.text("100%", at: NSPoint(x: 40, y: 60), size: 18, color: .gray)
            Fixtures.text("50%", at: NSPoint(x: 50, y: 230), size: 18, color: .gray)
            Fixtures.text("Days since learning", at: NSPoint(x: 380, y: 475), size: 20, weight: .medium, color: .darkGray)
            for day in 1...7 {
                Fixtures.text("\(day)", at: NSPoint(x: origin.x + CGFloat(day) * 100 - 6, y: 440), size: 18, color: .gray)
            }
            let curve = NSBezierPath()
            for step in 0...140 {
                let days = Double(step) / 20
                let point = NSPoint(x: origin.x + CGFloat(days * 100), y: 70 + CGFloat((1 - exp(-days / 1.6)) * 330))
                step == 0 ? curve.move(to: point) : curve.line(to: point)
            }
            NSColor.systemRed.setStroke()
            curve.lineWidth = 4
            curve.stroke()
        }
    }
}
#endif
