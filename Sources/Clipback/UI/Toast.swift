import AppKit
import SwiftUI

/// A small pill near the bottom of the screen that confirms an action and fades out on its own.
@MainActor
final class Toast {
    static let shared = Toast()

    private lazy var panel = makePanel()
    private var hideTask: Task<Void, Never>?

    func show(_ text: String) {
        let host = NSHostingView(rootView: ToastView(text: text))
        let size = host.fittingSize
        panel.contentView = host

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let area = screen.visibleFrame
        panel.setFrame(NSRect(x: area.midX - size.width / 2, y: area.minY + 48, width: size.width, height: size.height), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        fade(to: 1, duration: 0.18)

        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            fade(to: 0, duration: 0.25)
            try? await Task.sleep(for: .seconds(0.25))
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }

    private func fade(to alpha: CGFloat, duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            panel.animator().alphaValue = alpha
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.sharingType = .none
        return panel
    }
}

private struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .fontWeight(.medium)
            .toastCapsule()
            .padding(16)
            .fixedSize()
    }
}

extension View {
    /// The floating pill used for confirmations: the toast, and the review window's Undo bar.
    func toastCapsule() -> some View {
        font(.system(size: 13))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }
}
