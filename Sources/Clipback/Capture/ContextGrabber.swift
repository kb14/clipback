import AppKit
import ApplicationServices
import ClipbackCore

/// Everything known about the frontmost app at the moment the hotkey fires.
struct GrabbedContext {
    var appIcon: NSImage?
    var source: ClipSource
    var selection: String?
    var before: String?
    var after: String?
    /// How the selection was obtained, for the capture log.
    var method = "none"
    /// The focused element is a password field.
    var isSecure = false
    /// The app reports a non-empty selection, even if its text couldn't be read yet.
    var hasSelection = false
    /// Frame of the focused window in global top-left coordinates, for the screenshot attached to text clips.
    var windowFrame: CGRect?
}

/// Reads the selection and its source from the frontmost app. Must run before any Clipback window appears,
/// because showing one can change focus.
@MainActor
enum ContextGrabber {
    private static let contextRadius = 600

    static func grab(from app: NSRunningApplication) -> GrabbedContext {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.4)
        // Electron and Chromium only build their accessibility tree once a client asks for it.
        AX.setFlag(axApp, "AXManualAccessibility", true)

        let window = AX.element(axApp, kAXFocusedWindowAttribute)
        let title = window.flatMap { AX.string($0, kAXTitleAttribute) }
        let document = window.flatMap { AX.string($0, kAXDocumentAttribute) }

        let source = ClipSource(
            app: app.localizedName ?? "Unknown app",
            bundleID: app.bundleIdentifier,
            window: title.flatMap { $0.isEmpty ? nil : $0 },
            url: BrowserURL.current(bundleID: app.bundleIdentifier, window: window),
            file: document.flatMap(filePath(from:)),
            page: title.flatMap(pdfPage(from:))
        )
        var context = GrabbedContext(appIcon: app.icon, source: source)
        context.windowFrame = window.flatMap(AX.frame)
        let focused = AX.element(axApp, kAXFocusedUIElementAttribute)
        if let focused, AX.string(focused, kAXSubroleAttribute) == kAXSecureTextFieldSubrole {
            context.isSecure = true
            return context
        }

        guard let focused else { return context }
        // Asking only for the selection's range is instant even when the selection is a whole terminal scrollback,
        // so it tells us whether to wait longer for the text itself.
        context.hasSelection = (AX.range(focused, kAXSelectedTextRangeAttribute)?.length ?? 0) > 0
        if context.hasSelection { AXUIElementSetMessagingTimeout(focused, 1.5) }

        if let selected = AX.string(focused, kAXSelectedTextAttribute),
           !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            context.selection = selected
            context.hasSelection = true
            context.method = "accessibility"
            (context.before, context.after) = surroundingText(of: focused)
        }
        return context
    }

    /// Text on either side of the selection, when the focused element exposes its full value (text views, terminals).
    private static func surroundingText(of element: AXUIElement) -> (String?, String?) {
        guard let full = AX.string(element, kAXValueAttribute),
              let range = AX.range(element, kAXSelectedTextRangeAttribute) else { return (nil, nil) }
        let text = full as NSString
        let selectionEnd = range.location + range.length
        guard range.location >= 0, range.length > 0, selectionEnd <= text.length else { return (nil, nil) }

        let start = max(0, range.location - contextRadius)
        let end = min(text.length, selectionEnd + contextRadius)
        let before = text.substring(with: NSRange(location: start, length: range.location - start))
        let after = text.substring(with: NSRange(location: selectionEnd, length: end - selectionEnd))
        let (head, tail) = ClipMarkdown.trimContext(before: before, after: after, wasCutBefore: start > 0, wasCutAfter: end < text.length)
        return (head.isEmpty ? nil : head, tail.isEmpty ? nil : tail)
    }

    /// Chrome, Chromium browsers and Electron apps (Claude, Slack, Cursor, VS Code) all ship a Chromium framework.
    static func isChromiumBased(_ app: NSRunningApplication) -> Bool {
        guard let frameworks = app.bundleURL?.appending(path: "Contents/Frameworks"),
              let names = try? FileManager.default.contentsOfDirectory(atPath: frameworks.path) else { return false }
        let markers = ["Electron Framework", "Chrome Framework", "Chromium Framework", "Brave Browser Framework", "Edge Framework"]
        return names.contains { name in markers.contains { name.contains($0) } }
    }

    private static func filePath(from document: String) -> String? {
        guard let url = URL(string: document), url.isFileURL else { return nil }
        return url.path(percentEncoded: false)
    }

    /// Preview puts the page in the window title, e.g. "paper.pdf – Page 4 of 12".
    private static func pdfPage(from title: String) -> Int? {
        title.firstMatch(of: /Page (\d+)/).flatMap { Int($0.output.1) }
    }
}
