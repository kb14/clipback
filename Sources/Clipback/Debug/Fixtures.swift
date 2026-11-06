#if DEBUG
import AppKit
import ClipbackCore

/// Made-up clips covering every kind of source, written into a throwaway vault so the snapshot tool can check
/// how each one renders. Never touches the real vault.
enum Fixtures {
    enum Refusal: Error { case notATemporaryFolder(String) }

    /// Empties `vault` for made-up clips. They replace the whole folder, so they only ever go into a temporary
    /// folder, never a real vault.
    static func clearThrowaway(_ vault: URL) throws {
        let temporary = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath().path
        let target = vault.resolvingSymlinksInPath().path
        guard target.hasPrefix(temporary + "/"), target != AppSettings.defaultVaultURL.resolvingSymlinksInPath().path else {
            throw Refusal.notATemporaryFolder(target)
        }
        try? FileManager.default.removeItem(at: vault)
    }

    static func write(into vault: URL) throws {
        let fileManager = FileManager.default
        try clearThrowaway(vault)
        let work = vault.appending(path: "Work/2026/10")
        let personal = vault.appending(path: "Personal/2026/10")
        try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: personal, withIntermediateDirectories: true)

        let people = [
            Person(handle: "Maya", name: "Maya Chen"), Person(handle: "Leo", name: "Leo Park"),
            Person(handle: "Priya", name: "Priya Nair"), Person(handle: "SamRivera", name: "Sam Rivera"),
            Person(handle: "Omar", name: "Omar Haddad"),
        ]
        try JSONEncoder().encode(people).write(to: vault.appending(path: "Work/people.json"))

        var minutes = 0
        func save(_ clip: Clip, in folder: URL, name: String, image: NSImage? = nil) throws {
            minutes += 25
            var clip = clip
            clip.created = Date().addingTimeInterval(TimeInterval(-60 * minutes))
            if let image {
                clip.image = "\(name).png"
                try png(image).write(to: folder.appending(path: "\(name).png"))
            }
            try Data(ClipMarkdown.render(clip).utf8).write(to: folder.appending(path: "\(name).md"))
        }

        try save(Clip(library: .work, intent: .call, person: "Maya", title: "Planning and Next Steps",
                      source: ClipSource(app: "Granola", bundleID: "com.granola.app", window: "Granola"),
                      selection: """
                      # Planning and Next Steps

                      - Leo to review Omar's sync branch, keep the reusable parts, and write up a proper plan
                      - Agree on the API shape and the storage format before building more
                        - API shape first
                        - storage format second
                      - I'll draft a task plan (**one markdown file** with stories, owners and milestones)
                      1. Omar to rejoin after ~15 minutes
                      """,
                      note: "Discuss in standup tomorrow @Maya @Leo @Omar"), in: work, name: "granola-markdown")

        try save(Clip(library: .work, intent: .call, person: "Priya", title: "WHAT'S NEXT",
                      source: ClipSource(app: "Preview", bundleID: "com.apple.Preview", window: "Q4 Roadmap.pdf – Page 9 of 9",
                                         file: "/Users/example/Downloads/Q4 Roadmap.pdf", page: 9),
                      kind: .region, ocr: "WHAT'S NEXT\nFrom beta to daily use\nImport existing notes\nSync across two Macs",
                      selection: "", note: "Roadmap items left with @Priya"),
                 in: work, name: "preview-slide", image: slide())

        try save(Clip(library: .work, intent: .call, person: "Priya", title: "Speculative decoding in one pass",
                      source: ClipSource(app: "Google Chrome", bundleID: "com.google.Chrome",
                                         window: "Speculative decoding - Google Chrome", url: "https://cerebras.ai/blog/spec?utm_source=x"),
                      selection: "A small draft model proposes several tokens and the large model verifies them all in a single forward pass.",
                      before: "Latency at this scale is dominated by memory bandwidth, not compute. ",
                      after: " Acceptance rates above 70% are common for code."), in: work, name: "chrome-plain")

        try save(Clip(library: .work, intent: .call, person: "SamRivera", title: "the play button needs two clicks",
                      source: ClipSource(app: "Slack", bundleID: "com.tinyspeck.slackmacgap", window: "Sam Rivera (DM) - Slack"),
                      selection: "the play button on the feedback page needs two clicks\nSam Rivera  [9:34 PM]\nonly sometimes though\n[9:35 PM] maybe 3 in 8 tries",
                      note: "@SamRivera", done: Date()), in: work, name: "slack-done")

        let longReply = (1...14).map { "Paragraph \($0). The rollout went to staging first, then to production in batches of 100, and none have failed so far. We watched the error budget closely." }
            .joined(separator: "\n\n")
        try save(Clip(library: .work, intent: .call, title: "The rollout went to staging first",
                      source: ClipSource(app: "Claude", bundleID: "com.anthropic.claudefordesktop", window: "Claude"),
                      selection: longReply, note: "upload stats for the weekly update"), in: work, name: "claude-long-unassigned")

        try save(Clip(library: .work, intent: .call, person: "Maya", title: "Note apps compared",
                      source: ClipSource(app: "Claude", bundleID: "com.anthropic.claudefordesktop", window: "Claude"),
                      kind: .window, ocr: "Note apps compared\nCompare price and features",
                      selection: "", note: "pricing comparison for @Maya"), in: work, name: "claude-window", image: window())

        try save(Clip(library: .work, intent: .call, person: "Leo", title: "Screenshot from Figma",
                      source: ClipSource(app: "Figma", bundleID: "com.figma.Desktop", window: "Onboarding v3"),
                      kind: .region, image: "missing.png", selection: "", note: "check the onboarding step 3 copy @Leo"),
                 in: work, name: "missing-image")

        try save(Clip(library: .work, intent: .call, person: "Leo", title: "Context is a budget",
                      source: ClipSource(app: "Safari", bundleID: "com.apple.Safari", window: "Effective context engineering",
                                         url: "https://www.anthropic.com/engineering/context#budget"),
                      selection: "Treat context as a **finite resource** with diminishing returns. See [the guide](https://example.com).",
                      note: "@Leo for the design review"), in: work, name: "safari-inline")

        try save(Clip(library: .personal, intent: .revise, tags: ["learning"], title: "Retrieval beats rereading",
                      source: ClipSource(app: "Safari", bundleID: "com.apple.Safari", window: "How we remember",
                                         url: "https://example.com/how-we-remember"),
                      selection: "Trying to recall something strengthens memory far more than reading it again. Spacing those attempts out over days makes the effect larger still.",
                      note: "why the daily review works", review: ReviewState(next: Date())),
                 in: personal, name: "revise-due")
    }

    static func png(_ image: NSImage) throws -> Data {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        return data
    }

    static func draw(_ size: NSSize, _ body: @escaping (NSRect) -> Void) -> NSImage {
        NSImage(size: size, flipped: true) { rect in
            body(rect)
            return true
        }
    }

    static func text(_ string: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor) {
        (string as NSString).draw(at: point, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
    }

    /// A presentation slide, like a page of a PDF deck.
    private static func slide() -> NSImage {
        draw(NSSize(width: 1280, height: 720)) { rect in
            NSColor(white: 0.97, alpha: 1).setFill()
            rect.fill()
            text("WHAT'S NEXT", at: NSPoint(x: 80, y: 70), size: 56, weight: .bold, color: .black)
            text("From beta to daily use", at: NSPoint(x: 80, y: 150), size: 30, color: .darkGray)
            for (index, line) in ["Import existing notes", "Sync across two Macs", "Share a clip as a link"].enumerated() {
                text("•  \(line)", at: NSPoint(x: 100, y: 250 + CGFloat(index) * 70), size: 32, color: .black)
            }
        }
    }

    /// A whole app window with a sidebar and a conversation.
    private static func window() -> NSImage {
        draw(NSSize(width: 1400, height: 900)) { rect in
            NSColor(white: 0.12, alpha: 1).setFill()
            rect.fill()
            NSColor(white: 0.17, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 300, height: 900).fill()
            text("Note apps compared", at: NSPoint(x: 360, y: 60), size: 30, weight: .semibold, color: .white)
            for index in 0..<8 {
                text("Compare price and features across note apps, line \(index + 1).", at: NSPoint(x: 360, y: 150 + CGFloat(index) * 60),
                     size: 22, color: NSColor(white: 0.85, alpha: 1))
            }
        }
    }
}
#endif
