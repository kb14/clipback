import AppKit
import Sparkle

/// In-app updates through Sparkle, from the feed on GitHub Releases (`SUFeedURL` in Info.plist). Sparkle asks on
/// the second launch whether to check automatically, then checks about once a day; the choice lives in Sparkle's own
/// settings, which Settings → General edits. Debug builds never start it, so test copies don't check for or install
/// updates.
@MainActor
final class Updater: NSObject {
    private let windows: WindowManager
    private(set) var controller: SPUStandardUpdaterController!

    init(windows: WindowManager) {
        self.windows = windows
        super.init()
        #if DEBUG
        let start = false
        #else
        let start = true
        #endif
        controller = SPUStandardUpdaterController(startingUpdater: start, updaterDelegate: nil, userDriverDelegate: self)
    }

    var updater: SPUUpdater { controller.updater }
}

/// Clipback lives in the menubar, so an update found by the daily check would open behind other apps. Sparkle's
/// "gentle reminders": while its window is up, Clipback shows in the Dock, with a badge until the user looks at it.
extension Updater: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        NSApp.setActivationPolicy(.regular)
        if !state.userInitiated { NSApp.dockTile.badgeLabel = "1" }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        NSApp.dockTile.badgeLabel = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        NSApp.dockTile.badgeLabel = nil
        windows.leaveDockIfIdle()
    }
}
