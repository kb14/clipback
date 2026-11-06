import AppKit
import ServiceManagement

enum LoginItem {
    /// Which copy of Clipback last registered itself to launch at login.
    static let registeredPathKey = "loginItemPath"
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let windows = WindowManager()
    private var menuBar: MenuBarController?

    /// A login item registered by an earlier copy of Clipback (e.g. the development build) would keep launching
    /// that copy. The installed app re-registers itself so login always opens /Applications/Clipback.app.
    /// Done once per move, tracked by the path that last registered, so macOS doesn't announce a new login item
    /// on every launch.
    private func refreshLoginItem() {
        let path = Bundle.main.bundlePath
        guard path.hasPrefix("/Applications/"), SMAppService.mainApp.status == .enabled,
              UserDefaults.clipback.string(forKey: LoginItem.registeredPathKey) != path else { return }
        try? SMAppService.mainApp.unregister()
        try? SMAppService.mainApp.register()
        UserDefaults.clipback.set(path, forKey: LoginItem.registeredPathKey)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows.reopen()
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        refreshLoginItem()
        Vault.bootstrap()
        AppSettings.shared.applyAppearance()
        NSApp.mainMenu = MainMenu.make()
        ClipLibrary.shared.start()
        menuBar = MenuBarController(windows: windows)
        Hotkeys.register(
            onCapture: { CaptureCoordinator.shared.trigger() },
            onOpenClipback: { [windows] in windows.showLibrary() }
        )
        #if DEBUG
        // Lets scripts open the review window from outside, the way the hotkey or menubar does.
        DistributedNotificationCenter.default().addObserver(forName: .init("io.github.kb14.clipback.debug.openLibrary"), object: nil, queue: .main) {
            [windows] _ in MainActor.assumeIsolated { windows.showLibrary() }
        }
        // Runs the Screen Recording request without opening System Settings, to check in tccd's log that
        // Clipback gets registered.
        if CommandLine.arguments.contains("--request-screen-recording") {
            Task {
                await Permission.screenRecording.request(openingSettings: false)
                try? await Task.sleep(for: .seconds(1))
                NSApp.terminate(nil)
            }
            return
        }
        if let folder = DeveloperRun.value(after: "--share-test") {
            UISnapshotter.runShareTest(into: URL(fileURLWithPath: folder), windows: windows)
            return
        }
        if let folder = DeveloperRun.value(after: "--ui-snapshots") {
            UISnapshotter.run(into: URL(fileURLWithPath: folder), windows: windows)
            return
        }
        #endif
        // Screen Recording only takes effect after macOS's Quit & Reopen, so when Clipback was waiting on it the
        // setup window comes back to show everything ticked.
        if !Permission.allGranted || Permission.awaitingReady {
            windows.showOnboarding()
        }
    }
}
