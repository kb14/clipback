import AppKit
import ApplicationServices
import CoreGraphics
@preconcurrency import ScreenCaptureKit

/// The macOS privacy permissions Clipback needs before it can capture from other apps.
enum Permission: CaseIterable, Identifiable {
    case accessibility
    case screenRecording

    var id: Self { self }

    static var allGranted: Bool { allCases.allSatisfy(\.isGranted) }

    var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .screenRecording: "Screen Recording"
        }
    }

    var reason: String {
        switch self {
        case .accessibility: "Reads the text you select and which window it came from."
        case .screenRecording: "Takes the screenshot when you clip a region or window."
        }
    }

    var symbol: String {
        switch self {
        case .accessibility: "hand.point.up.left"
        case .screenRecording: "rectangle.dashed.badge.record"
        }
    }

    /// Screen Recording status is cached by macOS per process, so a grant only shows up here after a relaunch.
    var isGranted: Bool {
        switch self {
        case .accessibility: AXIsProcessTrusted()
        case .screenRecording: CGPreflightScreenCaptureAccess()
        }
    }

    /// Whether Clipback has asked for this before. macOS shows its own prompt only the first time.
    var hasAsked: Bool {
        get { UserDefaults.clipback.bool(forKey: Keys.asked(self)) }
        nonmutating set { UserDefaults.clipback.set(newValue, forKey: Keys.asked(self)) }
    }

    /// Set while Clipback waits on Screen Recording, which only takes effect after macOS's Quit & Reopen, so the
    /// next launch can show the setup window again as ready.
    static var awaitingReady: Bool {
        get { UserDefaults.clipback.bool(forKey: Keys.awaitingReady) }
        set { UserDefaults.clipback.set(newValue, forKey: Keys.awaitingReady) }
    }

    private enum Keys {
        static func asked(_ permission: Permission) -> String { "asked.\(permission)" }
        static let awaitingReady = "permissions.awaitingReady"
    }

    /// The first time, macOS may show its own prompt. When it does, that prompt has its own Open System Settings
    /// button, so Clipback leaves it alone; opening Settings as well would strand the prompt behind it. When it
    /// doesn't (macOS prompts once per app, then logs "does not allow prompting"), Settings is opened instead.
    @MainActor
    func request(openingSettings: Bool = true) async {
        let firstTime = !hasAsked
        hasAsked = true
        let promptsBefore = Self.promptWindows()
        switch self {
        case .accessibility:
            if firstTime {
                let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
            }
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        }
        if firstTime, await Self.promptAppears(besides: promptsBefore) { return }
        if self == .screenRecording {
            // Without a prompt the app may not be listed in System Settings. Asking ScreenCaptureKit for the
            // screen's content registers Clipback there, switched off, ready for the user to turn on.
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            } catch {
                Log.capture.info("Screen Recording not granted yet: \(error.localizedDescription, privacy: .public)")
            }
        }
        if openingSettings { openSettings() }
    }

    /// On-screen windows of universalAccessAuthWarn, which draws macOS's permission prompts for every app. They're
    /// listed by owner even before Screen Recording is allowed.
    private static func promptWindows() -> Set<Int> {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return Set(windows.compactMap { window in
            (window[kCGWindowOwnerName as String] as? String) == "universalAccessAuthWarn"
                ? window[kCGWindowNumber as String] as? Int : nil
        })
    }

    /// Whether a new prompt shows up within a second or so. One that was already open (say, another app's) doesn't
    /// count.
    @MainActor
    private static func promptAppears(besides earlier: Set<Int>) async -> Bool {
        for _ in 0..<8 {
            if !promptWindows().subtracting(earlier).isEmpty { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }

    func openSettings() {
        let anchor = switch self {
        case .accessibility: "Privacy_Accessibility"
        case .screenRecording: "Privacy_ScreenCapture"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor
    static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; open \"\(Bundle.main.bundlePath)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}
