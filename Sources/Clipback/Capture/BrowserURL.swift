import ApplicationServices
import Foundation

/// The address of the current tab in the frontmost browser.
@MainActor
enum BrowserURL {
    /// Chromium browsers share Chrome's AppleScript dictionary.
    private static let scripts: [String: String] = {
        var scripts = ["com.apple.Safari": "tell application id \"com.apple.Safari\" to return URL of current tab of front window"]
        for id in ["com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser"] {
            scripts[id] = "tell application id \"\(id)\" to return URL of active tab of front window"
        }
        return scripts
    }()

    /// Browsers without usable AppleScript; the URL comes from the accessibility tree instead.
    private static let accessibilityOnly: Set<String> = ["company.thebrowser.dia"]

    static func isBrowser(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return scripts[bundleID] != nil || accessibilityOnly.contains(bundleID)
    }

    /// The first AppleScript call per browser triggers macOS's one-time "Clipback wants to control …" prompt.
    static func current(bundleID: String?, window: AXUIElement?) -> String? {
        guard let bundleID, isBrowser(bundleID) else { return nil }
        if let source = scripts[bundleID], let url = runAppleScript(source), !url.isEmpty {
            return url
        }
        guard let window else { return nil }
        let webArea = AX.first(under: window) { AX.role($0) == "AXWebArea" }
        return webArea.flatMap { AX.url($0, kAXURLAttribute) }
    }

    private static func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            Log.capture.error("Browser URL AppleScript failed: \(error, privacy: .public)")
        }
        return result?.stringValue
    }
}
