import AppKit
import ClipbackCore
import SwiftUI

/// Owns Clipback's regular windows. Clipback lives in the menubar, but while any of these windows is open it also
/// shows in the Dock and ⌘Tab like a normal app, so the window can't get lost behind others.
@MainActor
final class WindowManager {
    private var windows: [String: NSWindow] = [:]
    private var closeObservers: [String: NSObjectProtocol] = [:]

    /// Opens the review window, optionally at a section of a given library.
    func showLibrary(_ section: SidebarItem? = nil, in library: Library? = nil) {
        if let library {
            ClipLibrary.shared.library = library
        } else if windows["library"]?.isVisible != true {
            // Opening fresh starts on the library captures go to right now (Work in work hours).
            ClipLibrary.shared.library = AppSettings.shared.captureLibrary()
        }
        if let section {
            // Set after the library switch, which resets the sidebar to Inbox.
            DispatchQueue.main.async { LibraryNavigation.shared.sidebar = section }
        }
        ClipLibrary.shared.reload()
        show(id: "library", title: "Clipback", size: NSSize(width: 1120, height: 720), resizable: true) {
            LibraryView()
        }
    }

    func showSettings() {
        show(id: "settings", title: "Clipback Settings", size: NSSize(width: 520, height: 520), resizable: false) {
            SettingsView(onReviewPermissions: { [weak self] in self?.showOnboarding() })
        }
    }

    func showOnboarding() {
        show(id: "onboarding", title: "Set up Clipback", size: NSSize(width: 560, height: 480), resizable: false) {
            OnboardingView(
                onDone: { [weak self] in self?.close(id: "onboarding") },
                onOpenClipback: { [weak self] in
                    self?.close(id: "onboarding")
                    self?.showLibrary()
                }
            )
        }
    }

    private func show<Content: View>(id: String, title: String, size: NSSize, resizable: Bool, content: () -> Content) {
        let window = windows[id] ?? makeWindow(title: title, size: size, resizable: resizable, content: content())
        windows[id] = window
        if closeObservers[id] == nil {
            closeObservers[id] = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.windowWillClose(id) }
            }
        }
        bringToFront(window)
    }

    /// The newer polite `NSApp.activate()` is ignored right after a menubar app switches to showing a Dock icon,
    /// so this uses the older forceful call, which macOS still honours. It runs again on the next turn of the
    /// run loop, after the switch and any menu tracking have finished.
    private func bringToFront(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// The Dock icon goes away again once the last window closes.
    private func windowWillClose(_ id: String) {
        let othersOpen = windows.contains { $0.key != id && $0.value.isVisible }
        if !othersOpen { NSApp.setActivationPolicy(.accessory) }
    }

    /// Clicking the Dock icon with no window open brings the review window back.
    func reopen() {
        if !windows.values.contains(where: \.isVisible) { showLibrary() }
    }

    func window(_ id: String) -> NSWindow? { windows[id] }

    private func close(id: String) {
        windows[id]?.close()
    }

    private func makeWindow<Content: View>(title: String, size: NSSize, resizable: Bool, content: Content) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        // Resizable windows host a split view whose sidebar should run up under the title bar.
        if resizable { style.formUnion([.resizable, .fullSizeContentView]) }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        window.title = title
        // macOS saves window sizes in the user's own settings, so a developer run (which resizes windows for
        // snapshots) mustn't turn this on.
        if resizable && !DeveloperRun.isActive { window.setFrameAutosaveName("Clipback.\(title)") }
        window.contentViewController = NSHostingController(rootView: content)
        window.setContentSize(size)
        window.isReleasedWhenClosed = false
        // Keep clips out of screen shares and recordings.
        window.sharingType = .none
        window.center()
        return window
    }
}
