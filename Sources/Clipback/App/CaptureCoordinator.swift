import AppKit
import ClipbackCore

/// Runs a capture end to end. With text selected it makes a text clip (plus a screenshot of that window);
/// with nothing selected it freezes the screen and lets you pick a region or window.
@MainActor
final class CaptureCoordinator {
    static let shared = CaptureCoordinator()

    private static let blockedApps: Set<String> = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
        "com.apple.Passwords", "com.apple.keychainaccess",
    ]

    private let panel = CapturePanelController()
    private let regionPicker = RegionPicker()
    private var isCapturing = false

    private init() {
        panel.onSave = { [weak self] draft in self?.save(draft) }
        panel.onDiscard = { Toast.shared.show("Discarded") }
    }

    func trigger() {
        if panel.isVisible {
            panel.focus()
            return
        }
        guard !isCapturing else { return }
        if AppSettings.shared.isPaused {
            Toast.shared.show("Capture is paused")
            return
        }
        guard Permission.accessibility.isGranted else {
            Toast.shared.show("Clipback needs Accessibility permission. Open Settings from the menubar")
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        if let bundleID = app.bundleIdentifier, Self.blockedApps.contains(bundleID) {
            Toast.shared.show("Clipback doesn't capture from password managers")
            return
        }

        isCapturing = true
        let started = ContinuousClock.now
        let context = ContextGrabber.grab(from: app)
        logTiming("Read selection and source", since: started)
        if context.isSecure {
            isCapturing = false
            Toast.shared.show("Clipback doesn't capture from password fields")
            return
        }

        Task {
            defer { isCapturing = false }
            await capture(from: app, context: context, started: started)
        }
    }

    private func capture(from app: NSRunningApplication, context: GrabbedContext, started: ContinuousClock.Instant) async {
        var context = context
        let screen = ScreenGrabber.screenUnderMouse()
        let canScreenshot = Permission.screenRecording.isGranted

        // Freeze the screen before anything of Clipback's appears. It runs alongside the copy below rather than
        // before it, since neither changes what's on screen.
        let screenshot: Task<CGImage?, Never>? = canScreenshot ? Task {
            do {
                return try await ScreenGrabber.captureDisplay(screen)
            } catch {
                Log.capture.error("Screen capture failed: \(error, privacy: .public)")
                return nil
            }
        } : nil

        // Chromium's accessibility text drops paragraph breaks, while ⌘C keeps them, so copy is tried first there.
        if ContextGrabber.isChromiumBased(app) || context.selection == nil,
           let copied = await TextFallback.copySelection(from: app.processIdentifier, timeout: context.hasSelection ? .seconds(2) : .milliseconds(200))
               .map(TextCleaner.clean), !copied.isEmpty {
            context.selection = copied
            context.method = "copy"
        }
        context.selection = context.selection.map(TextCleaner.clean).flatMap { $0.isEmpty ? nil : $0 }
        let frozen = await screenshot?.value
        logCapture(context)

        if let selection = context.selection {
            let windowShot = both(frozen, context.windowFrame).flatMap { ScreenGrabber.crop($0, to: $1, on: screen) }
            present(CaptureDraft(context: context, selection: selection, image: windowShot,
                                 library: library(for: context), recentPeople: ClipStore.recentPeople, knownTags: ClipStore.recentTags))
            logTiming("Text panel shown", since: started)
            return
        }

        guard let frozen else {
            Toast.shared.show(canScreenshot
                ? "Couldn't take a screenshot. Try again"
                : "Select some text, or allow Screen Recording in Settings to clip a region")
            return
        }
        logTiming("Region picker shown", since: started)
        guard let pick = await regionPicker.pick(on: screen, frozen: frozen, windows: ScreenGrabber.visibleWindows()),
              let image = ScreenGrabber.crop(frozen, to: pick.rect, on: screen) else { return }

        let source = sourceContext(for: pick, frontmost: app, context: context)
        present(CaptureDraft(context: source, selection: "", kind: pick.kind, image: image,
                             library: library(for: source), recentPeople: ClipStore.recentPeople, knownTags: ClipStore.recentTags))
    }

    /// The window under the picked region is the source. When that's the app you were in, keep its URL and file.
    private func sourceContext(for pick: RegionPick, frontmost app: NSRunningApplication, context: GrabbedContext) -> GrabbedContext {
        guard let window = pick.window, window.ownerPID != app.processIdentifier else { return context }
        let owner = NSRunningApplication(processIdentifier: window.ownerPID)
        let source = ClipSource(app: owner?.localizedName ?? window.ownerName, bundleID: owner?.bundleIdentifier, window: window.title)
        return GrabbedContext(appIcon: owner?.icon, source: source)
    }

    private func library(for context: GrabbedContext) -> Library {
        LibraryGuesser(workRules: AppSettings.shared.workRules).guess(for: context.source, fallback: AppSettings.shared.captureLibrary())
    }

    private func present(_ draft: CaptureDraft) {
        panel.present(draft)
    }

    private func save(_ draft: CaptureDraft) {
        Task {
            await draft.waitForText()
            let clip = draft.makeClip()
            let encoded = await encode(draft.image, kind: draft.kind)
            do {
                let url = try ClipStore.save(clip, image: encoded)
                Log.store.info("Saved clip to \(url.path(percentEncoded: false), privacy: .public)")
                Toast.shared.show("Saved to \(clip.library.title) · \(clip.intent.title)")
            } catch {
                Log.store.error("Saving clip failed: \(error, privacy: .public)")
                Toast.shared.show("Couldn't save the clip: \(error.localizedDescription)")
            }
        }
    }

    /// Picked regions keep more detail than the background screenshot attached to a text clip.
    private func encode(_ image: CGImage?, kind: ClipKind) async -> EncodedImage? {
        guard let image else { return nil }
        let maxDimension = kind == .text ? 1600 : 2400
        let pngLimit = kind == .text ? 400_000 : 1_500_000
        return await Task.detached(priority: .userInitiated) {
            ImageEncoder.encode(image, maxDimension: maxDimension, pngLimit: pngLimit)
        }.value
    }

    /// How long from the hotkey to something on screen, to keep captures feeling instant.
    private func logTiming(_ what: String, since start: ContinuousClock.Instant) {
        let elapsed = (ContinuousClock.now - start).formatted(.units(allowed: [.milliseconds]))
        Log.capture.info("\(what, privacy: .public) after \(elapsed, privacy: .public)")
    }

    private func logCapture(_ context: GrabbedContext) {
        let source = context.source
        Log.capture.info("""
            Capture from \(source.app, privacy: .public) (\(source.bundleID ?? "?", privacy: .public)) \
            via \(context.method, privacy: .public); url=\(source.url != nil), file=\(source.file != nil), \
            page=\(source.page ?? 0), context=\(context.before != nil || context.after != nil), hasSelection=\(context.hasSelection), \
            window=\(context.windowFrame != nil)
            """)
    }
}

private func both<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}
