#if DEBUG
import AppKit
import ClipbackCore
@preconcurrency import ScreenCaptureKit

/// Developer tool: opens each screen of Clipback, saves a PNG of it, then quits. Lets layout be checked
/// without clicking through by hand. Run with `open build/Clipback.app --args --ui-snapshots <folder>`.
/// Clipback draws its own views into the image, so no screen recording is involved.
@MainActor
enum UISnapshotter {
    static func run(into folder: URL, windows: WindowManager) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        Task {
            let library = ClipLibrary.shared
            let navigation = LibraryNavigation.shared
            if CommandLine.arguments.contains("--fixtures") {
                await runFixtureTour(into: folder, windows: windows)
                NSApp.terminate(nil)
                return
            }
            if CommandLine.arguments.contains("--showcase") {
                await runShowcase(into: folder, windows: windows)
                NSApp.terminate(nil)
                return
            }
            for _ in 0..<40 where library.byLibrary.isEmpty { try? await Task.sleep(for: .milliseconds(100)) }

            let sizes = [("wide", NSSize(width: 1200, height: 760)), ("narrow", NSSize(width: 940, height: 600))]
            windows.showLibrary(.inbox, in: .personal)
            try? await Task.sleep(for: .milliseconds(600))
            guard let window = windows.window("library") else { NSApp.terminate(nil); return }

            for (sizeName, size) in sizes {
                window.setContentSize(size)
                @MainActor func shot(_ name: String) async {
                    try? await Task.sleep(for: .milliseconds(900))
                    save(window, to: folder.appending(path: "\(sizeName)-\(name).png"))
                }
                @MainActor func select(_ section: SidebarItem, in lib: Library, clip: ((Clip) -> Bool)? = nil) async {
                    library.library = lib
                    try? await Task.sleep(for: .milliseconds(150))
                    navigation.sidebar = section
                    try? await Task.sleep(for: .milliseconds(150))
                    if let clip { navigation.selectedID = library.activeClips.first { clip($0.clip) }?.id }
                }

                await select(.inbox, in: .personal, clip: { $0.kind == .text && $0.before != nil })
                await shot("inbox-text-context")
                await select(.inbox, in: .personal, clip: { $0.kind == .text && $0.selection.count > 2000 })
                await shot("inbox-text-long")
                await select(.inbox, in: .personal, clip: { $0.kind == .region })
                await shot("inbox-region")
                await select(.inbox, in: .personal, clip: { $0.kind == .window })
                await shot("inbox-window")
                await select(.today, in: .personal)
                await shot("today")
                await select(.calls, in: .work)
                await shot("calls")
                await select(.inbox, in: .work, clip: { $0.source.app == "Granola" })
                await shot("inbox-markdown")
                await select(.todo, in: .personal)
                await shot("todo")
                await select(.sources, in: .personal)
                await shot("sources")
                await select(.revise, in: .personal)
                await shot("revise")
                await select(.todo, in: .work)
                await shot("empty-todo")
                await select(.inbox, in: .personal)
                navigation.query = "claude"
                await shot("search")
                navigation.query = ""
            }

            await snapshotCapturePanel(folder: folder)
            windows.showOnboarding()
            try? await Task.sleep(for: .milliseconds(800))
            if let onboarding = windows.window("onboarding") { save(onboarding, to: folder.appending(path: "onboarding.png")) }
            // Settings shows KeyboardShortcuts' recorder, which loads that package's resource bundle.
            windows.showSettings()
            try? await Task.sleep(for: .milliseconds(800))
            if let settings = windows.window("settings") { save(settings, to: folder.appending(path: "settings.png")) }
            NSApp.terminate(nil)
        }
    }

    /// Renders Calls for every person in the made-up vault, plus the detail view of each kind of clip.
    private static func runFixtureTour(into folder: URL, windows: WindowManager) async {
        let library = ClipLibrary.shared
        let navigation = LibraryNavigation.shared
        do {
            try Fixtures.write(into: AppSettings.shared.vaultURL)
        } catch {
            print("fixtures: \(error)")
            return
        }
        library.reload()
        try? await Task.sleep(for: .milliseconds(800))
        windows.showLibrary(.calls, in: .work)
        try? await Task.sleep(for: .milliseconds(600))
        guard let window = windows.window("library") else { return }
        window.setContentSize(NSSize(width: 1200, height: 860))

        for person in ["Maya", "Priya", "Leo", "Not assigned", "SamRivera"] {
            library.library = .work
            navigation.sidebar = .calls
            try? await Task.sleep(for: .milliseconds(150))
            navigation.person = person
            try? await Task.sleep(for: .milliseconds(900))
            save(window, to: folder.appending(path: "fixture-calls-\(person.replacingOccurrences(of: " ", with: "-")).png"))
        }
        // Archive: the discussed Slack clip should be here, not in Inbox. Then archive one clip to show Undo.
        library.library = .work
        try? await Task.sleep(for: .milliseconds(200))
        navigation.sidebar = .archive
        try? await Task.sleep(for: .milliseconds(900))
        save(window, to: folder.appending(path: "fixture-archive.png"))
        navigation.sidebar = .inbox
        try? await Task.sleep(for: .milliseconds(300))
        if let figma = library.activeClips.first(where: { $0.clip.source.app == "Figma" }) {
            navigation.selectedID = figma.id
            // Like a person would: the clip is shown selected before it's archived.
            try? await Task.sleep(for: .milliseconds(400))
            library.archive(figma)
        }
        try? await Task.sleep(for: .milliseconds(900))
        save(window, to: folder.appending(path: "fixture-inbox-undo.png"))
        library.clearArchiveEvent()

        library.library = .personal
        try? await Task.sleep(for: .milliseconds(200))
        navigation.sidebar = .today
        try? await Task.sleep(for: .milliseconds(900))
        save(window, to: folder.appending(path: "fixture-today.png"))
        library.library = .work

        for name in ["Granola", "Preview", "Google Chrome", "Slack", "Figma", "Safari"] {
            navigation.sidebar = .inbox
            try? await Task.sleep(for: .milliseconds(150))
            navigation.selectedID = library.clips.first { $0.clip.source.app == name }?.id
            try? await Task.sleep(for: .milliseconds(900))
            save(window, to: folder.appending(path: "fixture-detail-\(name.replacingOccurrences(of: " ", with: "-")).png"))
        }
    }

    /// The README screenshots: a few days of ordinary-looking clips (`Showcase`), shown in the screens people see most.
    private static func runShowcase(into folder: URL, windows: WindowManager) async {
        let library = ClipLibrary.shared
        let navigation = LibraryNavigation.shared
        do {
            try Showcase.write(into: AppSettings.shared.vaultURL)
        } catch {
            print("showcase: \(error)")
            return
        }
        library.reload()
        try? await Task.sleep(for: .milliseconds(800))
        windows.showLibrary(.inbox, in: .personal)
        try? await Task.sleep(for: .milliseconds(600))
        guard let window = windows.window("library") else { return }
        window.setContentSize(NSSize(width: 1120, height: 680))

        library.library = .personal
        navigation.sidebar = .inbox
        try? await Task.sleep(for: .milliseconds(200))
        navigation.selectedID = library.activeClips.first { $0.clip.source.url?.contains("Spacing_effect") == true }?.id
        try? await Task.sleep(for: .milliseconds(900))
        save(window, to: folder.appending(path: "inbox.png"))

        navigation.sidebar = .today
        try? await Task.sleep(for: .milliseconds(900))
        save(window, to: folder.appending(path: "today.png"))

        library.library = .work
        try? await Task.sleep(for: .milliseconds(200))
        navigation.sidebar = .calls
        try? await Task.sleep(for: .milliseconds(150))
        navigation.person = "Leo"
        try? await Task.sleep(for: .milliseconds(900))
        save(window, to: folder.appending(path: "calls.png"))

        var context = GrabbedContext(
            appIcon: NSWorkspace.shared.icon(forFile: "/Applications/Safari.app"),
            source: ClipSource(app: "Safari", bundleID: "com.apple.Safari", window: "Testing effect - Wikipedia",
                               url: "https://en.wikipedia.org/wiki/Testing_effect")
        )
        context.selection = "The testing effect suggests long-term memory is increased when part of the learning period is devoted to retrieving information from memory."
        await snapshotCapturePanel(context, note: "quiz myself instead of rereading the Spanish notes #lea", library: .personal,
                                   tags: ["learning", "reading", "food"], to: folder.appending(path: "capture-panel.png"))
        if let demo = DeveloperRun.value(after: "--demo-frames") {
            await renderDemoFrames(textContext: context, into: URL(fileURLWithPath: demo))
        }
    }

    /// Frames for the README demo video: the real capture panel at each step of typing a note, for a text clip and
    /// a screenshot clip, plus the chart the screenshot is taken of. Only made-up showcase content.
    private static func renderDemoFrames(textContext: GrabbedContext, into folder: URL) async {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let tags = ["learning", "reading", "food"]
        let note = "quiz myself instead of rereading the Spanish notes #learning "
        let stops = [0, 5, 12, 20, 28, 36, 44, 51, 55, note.count - 1, note.count]
        for (index, length) in stops.enumerated() {
            await renderPanel(textContext, note: String(note.prefix(length)), intent: .save, tags: tags,
                              to: folder.appending(path: String(format: "text-%02d.png", index)))
        }
        await renderPanel(textContext, note: note, intent: .revise, tags: tags, to: folder.appending(path: "text-revise.png"))

        let chart = Showcase.forgettingCurve()
        if let tiff = chart.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            try? rep.representation(using: .png, properties: [:])?.write(to: folder.appending(path: "chart.png"))
        }
        guard let image = chart.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let regionContext = GrabbedContext(
            appIcon: NSWorkspace.shared.icon(forFile: "/Applications/Safari.app"),
            source: ClipSource(app: "Safari", bundleID: "com.apple.Safari", window: "Forgetting curve - Wikipedia",
                               url: "https://en.wikipedia.org/wiki/Forgetting_curve")
        )
        let regionNote = "each review flattens it"
        for (index, length) in [0, 4, 11, 17, regionNote.count].enumerated() {
            await renderPanel(regionContext, kind: .region, image: image, note: String(regionNote.prefix(length)),
                              intent: index == 4 ? .revise : .save, tags: tags,
                              to: folder.appending(path: String(format: "region-%02d.png", index)))
        }
    }

    private static func renderPanel(_ context: GrabbedContext, kind: ClipKind = .text, image: CGImage? = nil,
                                    note: String, intent: Intent, tags: [String], to url: URL) async {
        let draft = CaptureDraft(context: context, selection: context.selection ?? "", kind: kind, image: image,
                                 library: .personal, recentPeople: [], knownTags: tags)
        draft.note = note
        draft.intent = intent
        let controller = CapturePanelController()
        controller.present(draft)
        try? await Task.sleep(for: .milliseconds(kind == .text ? 500 : 1200))
        if let panel = NSApp.windows.last(where: { $0 is CapturePanel && $0.isVisible }) {
            // As if typed: the cursor at the end, nothing selected.
            if let field = panel.firstResponder as? NSTextView {
                field.setSelectedRange(NSRange(location: (field.string as NSString).length, length: 0))
            }
            try? await Task.sleep(for: .milliseconds(150))
            save(panel, to: url)
            panel.orderOut(nil)
        }
    }

    /// Captures the screen the way Zoom, Meet and Slack huddles do (ScreenCaptureKit, nothing excluded) while
    /// Clipback's window is open, to check whether the window leaks into screen shares.
    static func runShareTest(into folder: URL, windows: WindowManager) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var report: [String] = []
        // Launched with `open`, so results go to a file rather than stdout.
        func note(_ line: String) {
            report.append(line)
            try? report.joined(separator: "\n").write(to: folder.appending(path: "result.txt"), atomically: true, encoding: .utf8)
        }
        Task {
            windows.showLibrary(.inbox, in: .personal)
            try? await Task.sleep(for: .seconds(1.5))
            guard let window = windows.window("library"), let screen = window.screen ?? NSScreen.main else {
                NSApp.terminate(nil)
                return
            }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let pid = ProcessInfo.processInfo.processIdentifier
                let listed = content.windows.filter { $0.owningApplication?.processID == pid }
                note("Clipback windows offered to sharing apps: \(listed.count)")
                let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw ScreenGrabber.Failure.displayNotFound }
                let config = SCStreamConfiguration()
                config.width = Int(CGFloat(display.width) * screen.backingScaleFactor)
                config.height = Int(CGFloat(display.height) * screen.backingScaleFactor)
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: config)
                let rep = NSBitmapImageRep(cgImage: image)
                try rep.representation(using: .png, properties: [:])?.write(to: folder.appending(path: "screen-share-view.png"))
                note("Clipback window frame \(window.frame); saved what a sharing app would see")
            } catch {
                note("failed: \(error)")
            }
            NSApp.terminate(nil)
        }
    }

    private static func snapshotCapturePanel(folder: URL) async {
        var context = GrabbedContext(
            appIcon: NSWorkspace.shared.icon(forFile: "/Applications/Google Chrome.app"),
            source: ClipSource(app: "Google Chrome", bundleID: "com.google.Chrome",
                               window: "Speculative decoding at wafer scale - Google Chrome", url: "https://cerebras.ai/blog/spec")
        )
        context.selection = "A small draft model proposes several tokens and the large model verifies them all in a single forward pass."
        await snapshotCapturePanel(context, note: "good one for the book club #rea", library: .personal,
                                   tags: ["reading", "books"], to: folder.appending(path: "capture-panel.png"))
    }

    private static func snapshotCapturePanel(_ context: GrabbedContext, note: String, library: Library, tags: [String], to url: URL) async {
        let draft = CaptureDraft(context: context, selection: context.selection ?? "", library: library,
                                 recentPeople: [], knownTags: tags)
        draft.note = note
        let controller = CapturePanelController()
        controller.present(draft)
        try? await Task.sleep(for: .milliseconds(700))
        if let panel = NSApp.windows.first(where: { $0 is CapturePanel }) {
            save(panel, to: url)
        }
    }

    /// Logs each scroll view's visible height against its content height, to catch panes that can't scroll.
    private static func reportScrollViews(in view: NSView, name: String) {
        if let scroll = view as? NSScrollView, let document = scroll.documentView {
            let visible = Int(scroll.contentView.bounds.height)
            let content = Int(document.frame.height)
            print("\(name): scroll view x=\(Int(scroll.frame.minX)) visible=\(visible) content=\(content)\(content > visible ? " scrollable" : "")")
        }
        view.subviews.forEach { reportScrollViews(in: $0, name: name) }
    }

    private static func save(_ window: NSWindow, to url: URL) {
        if let root = window.contentView { reportScrollViews(in: root, name: url.deletingPathExtension().lastPathComponent) }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
