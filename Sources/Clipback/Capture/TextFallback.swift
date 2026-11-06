import AppKit
import Carbon.HIToolbox

/// For apps that don't expose the selection through Accessibility (most Electron apps): press ⌘C on the
/// user's behalf, read the clipboard, then put the user's clipboard back exactly as it was.
@MainActor
enum TextFallback {
    private static let concealedTypes: Set<NSPasteboard.PasteboardType> = [
        .init("org.nspasteboard.ConcealedType"),
        .init("org.nspasteboard.TransientType"),
    ]

    /// `timeout` is how long to wait for the app to put the copy on the clipboard. Real copies land in 20–50 ms,
    /// so it's short when we don't know a selection exists (a screenshot capture shouldn't be held up) and longer
    /// when we know one does (very large copies are slower).
    static func copySelection(from pid: pid_t, timeout: Duration = .milliseconds(200)) async -> String? {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)
        let startCount = pasteboard.changeCount

        // No need to wait for the hotkey's ⌃⌥ to be let go: the ⌘C goes straight to the app, so held keys can't
        // mix into it.
        postCommandC(to: pid)

        var copied: String?
        let copyStart = ContinuousClock.now
        let deadline = copyStart + timeout
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
            guard pasteboard.changeCount != startCount else { continue }
            let types = Set(pasteboard.types ?? [])
            if types.isDisjoint(with: concealedTypes) {
                copied = pasteboard.string(forType: .string)
            }
            break
        }
        Log.capture.info("""
            Copy fallback: clipboard changed=\(pasteboard.changeCount != startCount) after \
            \((ContinuousClock.now - copyStart).formatted(.units(allowed: [.milliseconds])), privacy: .public)
            """)

        if pasteboard.changeCount != startCount {
            restore(saved, to: pasteboard)
        } else {
            restoreIfChangedLate(saved, startCount: startCount)
        }
        return copied
    }

    /// An app that finishes the copy after we stop waiting would otherwise leave its text on the user's clipboard.
    private static func restoreIfChangedLate(_ saved: [NSPasteboardItem], startCount: Int) {
        Task {
            try? await Task.sleep(for: .seconds(2))
            let pasteboard = NSPasteboard.general
            guard pasteboard.changeCount == startCount + 1 else { return }
            Log.capture.info("Copy fallback: clipboard changed late, restoring it")
            restore(saved, to: pasteboard)
        }
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    private static func restore(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }

    /// Sent straight to the app rather than through the system keyboard stream, which would merge in the ⌃⌥
    /// of the capture hotkey if it's still held and turn the copy into ⌃⌥⌘C.
    private static func postCommandC(to pid: pid_t) {
        let source = CGEventSource(stateID: .privateState)
        let keyC = CGKeyCode(kVK_ANSI_C)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: isDown)
            event?.flags = .maskCommand
            event?.postToPid(pid)
        }
    }
}
