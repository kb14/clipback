import AppKit
import KeyboardShortcuts
import ClipbackCore

/// The menubar icon and its menu. The icon shows how many clips wait in Today across both libraries.
/// The menu is rebuilt each time it opens so it always reflects current state.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let windows: WindowManager
    private let settings = AppSettings.shared
    private let clips = ClipLibrary.shared
    private var midnightTimer: Timer?

    init(windows: WindowManager) {
        self.windows = windows
        super.init()
        statusItem.button?.image = MenuBarIcon.image()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        clips.onReload = { [weak self] in self?.refreshIcon() }
        // The count changes at midnight even if no file does.
        midnightTimer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshIcon() }
        }
        refreshIcon()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let capture = item("Capture", #selector(capture))
        capture.setShortcut(for: .capture)
        menu.addItem(capture)
        let open = item("Open Clipback", #selector(openClipback))
        open.setShortcut(for: .openClipback)
        menu.addItem(open)

        menu.addItem(.separator())
        for library in Library.allCases {
            let due = clips.today(in: library).due.count
            guard due > 0 else { continue }
            let today = item("Today · \(due) to revise in \(library.title)", #selector(openToday(_:)))
            today.representedObject = library.rawValue
            today.image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: nil)
            menu.addItem(today)
        }
        for library in Library.allCases {
            let open = clips.activeClips(in: library).filter { $0.clip.intent == .call }
            let people = Set(open.flatMap(\.clip.people))
            guard !open.isEmpty else { continue }
            let title = people.isEmpty ? "\(open.count) to raise" : people.sorted().prefix(3).joined(separator: ", ")
            let calls = item("Calls · \(title) (\(library.title))", #selector(openCalls(_:)))
            calls.representedObject = library.rawValue
            calls.image = NSImage(systemSymbolName: "phone", accessibilityDescription: nil)
            menu.addItem(calls)
        }

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Capturing into"))
        for mode in CaptureMode.allCases {
            let title = switch mode {
            case .automatic: "Automatic · now \(settings.captureLibrary().title) (Work \(WorkHours.standard.summary))"
            case .personal: "Personal"
            case .work: "Work"
            }
            let modeItem = item(title, #selector(selectCaptureMode(_:)))
            modeItem.representedObject = mode.rawValue
            modeItem.state = settings.captureMode == mode ? .on : .off
            menu.addItem(modeItem)
        }

        menu.addItem(.separator())
        let pause = item("Pause capture", #selector(togglePause))
        pause.state = settings.isPaused ? .on : .off
        menu.addItem(pause)
        if !Permission.allGranted {
            menu.addItem(item("Set up permissions…", #selector(showOnboarding)))
        }
        menu.addItem(item("Settings…", #selector(showSettings), key: ","))
        menu.addItem(item("About Clipback", #selector(showAbout)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Clipback", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        return menuItem
    }

    private func refreshIcon() {
        statusItem.button?.appearsDisabled = settings.isPaused
        let due = Library.allCases.reduce(0) { $0 + clips.today(in: $1).due.count }
        statusItem.button?.title = due > 0 ? " \(due)" : ""
        statusItem.button?.imagePosition = .imageLeading
    }

    @objc private func capture() { CaptureCoordinator.shared.trigger() }
    @objc private func openClipback() { windows.showLibrary() }

    @objc private func openToday(_ sender: NSMenuItem) {
        windows.showLibrary(.today, in: (sender.representedObject as? String).flatMap(Library.init(rawValue:)))
    }

    @objc private func openCalls(_ sender: NSMenuItem) {
        windows.showLibrary(.calls, in: (sender.representedObject as? String).flatMap(Library.init(rawValue:)))
    }
    @objc private func showSettings() { windows.showSettings() }
    @objc private func showOnboarding() { windows.showOnboarding() }
    @objc private func quit() { NSApp.terminate(nil) }

    /// The standard About panel (icon, version, copyright from Info.plist) with a line on what Clipback does and a
    /// link to its GitHub page, where new releases are.
    @objc private func showAbout() {
        let credits = NSMutableAttributedString(
            string: "Save a quote or a screenshot from any Mac app, and see it again later.\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        credits.append(NSAttributedString(string: "github.com/kb14/clipback", attributes: [
            .font: NSFont.systemFont(ofSize: 11), .link: URL(string: "https://github.com/kb14/clipback")!,
        ]))
        let centred = NSMutableParagraphStyle()
        centred.alignment = .center
        credits.addAttribute(.paragraphStyle, value: centred, range: NSRange(location: 0, length: credits.length))
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    @objc private func selectCaptureMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = CaptureMode(rawValue: raw) else { return }
        settings.captureMode = mode
    }

    @objc private func togglePause() {
        settings.isPaused.toggle()
        refreshIcon()
    }
}
