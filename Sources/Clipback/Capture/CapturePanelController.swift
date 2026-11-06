import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A borderless panel that takes typing without activating Clipback, so the app you captured from stays in front.
final class CapturePanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .statusBar
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        sharingType = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Shows the capture panel and handles its keyboard: Return saves, Esc discards, ⌘1 to ⌘4 pick the intent,
/// ⌘L flips the library. The panel stays until you save or discard.
@MainActor
final class CapturePanelController {
    var onSave: ((CaptureDraft) -> Void)?
    var onDiscard: (() -> Void)?

    private let panel = CapturePanel()
    private var draft: CaptureDraft?
    private var anchor = NSPoint.zero
    private var eventMonitor: Any?

    var isVisible: Bool { panel.isVisible }

    func present(_ draft: CaptureDraft) {
        self.draft = draft
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        anchor = NSPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.minY + 40)

        let host = NSHostingView(rootView: CapturePanelView(draft: draft) { [weak self] size in
            self?.resize(to: size)
        })
        panel.contentView = host
        resize(to: host.fittingSize)
        panel.makeKeyAndOrderFront(nil)
        installEventMonitor()
    }

    func focus() {
        panel.makeKeyAndOrderFront(nil)
    }

    private func save() {
        guard let draft else { return }
        close()
        onSave?(draft)
    }

    private func discard() {
        close()
        onDiscard?()
    }

    private func close() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        panel.orderOut(nil)
        panel.contentView = nil
        draft = nil
    }

    /// Grows upward from a fixed bottom edge as suggestions or chips appear.
    private func resize(to size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        panel.setFrame(NSRect(x: anchor.x - size.width / 2, y: anchor.y, width: size.width, height: size.height), display: true)
        panel.invalidateShadow()
    }

    private func installEventMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return consumed ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let draft, event.window === panel else { return false }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command, let key = event.charactersIgnoringModifiers?.lowercased() {
            if let number = Int(key), (1...4).contains(number) {
                draft.selectIntent(number: number)
                return true
            }
            if key == "l" {
                draft.toggleLibrary()
                return true
            }
        }

        switch Int(event.keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if !draft.acceptSuggestion() { save() }
            return true
        case kVK_Tab:
            return draft.acceptSuggestion()
        case kVK_Escape:
            if draft.suggestions.isEmpty { discard() } else { draft.dismissSuggestions() }
            return true
        case kVK_DownArrow where !draft.suggestions.isEmpty:
            draft.moveHighlight(by: 1)
            return true
        case kVK_UpArrow where !draft.suggestions.isEmpty:
            draft.moveHighlight(by: -1)
            return true
        default:
            return false
        }
    }
}
