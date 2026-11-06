import AppKit
import Carbon.HIToolbox
import ClipbackCore

/// What the user picked on the frozen screen.
struct RegionPick {
    /// Global top-left coordinates.
    var rect: CGRect
    var kind: ClipKind
    /// The window under the pick, used as the clip's source.
    var window: ScreenWindow?
}

/// Shows a frozen, dimmed copy of the screen. Drag to pick a region, Space to switch to picking a whole
/// window, Esc to cancel.
@MainActor
final class RegionPicker {
    private var panel: NSPanel?
    private var continuation: CheckedContinuation<RegionPick?, Never>?

    func pick(on screen: NSScreen, frozen: CGImage, windows: [ScreenWindow]) async -> RegionPick? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let view = RegionPickerView(frame: CGRect(origin: .zero, size: screen.frame.size), frozen: frozen,
                                        windows: windows, screenOrigin: ScreenGrabber.origin(of: screen))
            view.onFinish = { [weak self] pick in self?.finish(pick) }

            let panel = OverlayPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.isOpaque = true
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.sharingType = .none
            panel.acceptsMouseMovedEvents = true
            panel.contentView = view
            panel.setFrame(screen.frame, display: true)
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(view)
            self.panel = panel
            NSCursor.crosshair.set()
        }
    }

    private func finish(_ pick: RegionPick?) {
        panel?.orderOut(nil)
        panel = nil
        NSCursor.arrow.set()
        continuation?.resume(returning: pick)
        continuation = nil
    }
}

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class RegionPickerView: NSView {
    var onFinish: ((RegionPick?) -> Void)?

    private let frozen: CGImage
    private let windows: [ScreenWindow]
    private let screenOrigin: CGPoint
    private var isWindowMode = false
    private var dragStart: CGPoint?
    private var selection: CGRect?
    private var hoveredWindow: ScreenWindow?

    init(frame: CGRect, frozen: CGImage, windows: [ScreenWindow], screenOrigin: CGPoint) {
        self.frozen = frozen
        self.windows = windows
        self.screenOrigin = screenOrigin
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate], owner: self))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(frozen, in: bounds)
        context.restoreGState()

        let highlight = isWindowMode ? hoveredWindow.map { localRect(for: $0.frame) } : selection
        let dim = NSBezierPath(rect: bounds)
        if let highlight { dim.append(NSBezierPath(rect: highlight)) }
        dim.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.42).setFill()
        dim.fill()

        if let highlight {
            if isWindowMode {
                NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
                NSBezierPath(rect: highlight).fill()
            }
            let border = NSBezierPath(rect: highlight.insetBy(dx: -0.75, dy: -0.75))
            border.lineWidth = 1.5
            (isWindowMode ? NSColor.controlAccentColor : NSColor.white).setStroke()
            border.stroke()
            if !isWindowMode { drawSizeLabel(for: highlight) }
        }
        drawHint()
    }

    private func drawSizeLabel(for rect: CGRect) {
        let text = "\(Int(rect.width)) × \(Int(rect.height))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white]
        let size = text.size(withAttributes: attributes)
        let box = CGRect(x: rect.maxX - size.width - 12, y: min(rect.maxY + 6, bounds.maxY - size.height - 8), width: size.width + 12, height: size.height + 4)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        text.draw(at: CGPoint(x: box.minX + 6, y: box.minY + 2), withAttributes: attributes)
    }

    private func drawHint() {
        let hint = isWindowMode
            ? "Click a window      space  drag a region      esc  cancel"
            : "Drag to clip a region      space  whole window      esc  cancel"
        let text = hint as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white]
        let size = text.size(withAttributes: attributes)
        let box = CGRect(x: bounds.midX - size.width / 2 - 14, y: 44, width: size.width + 28, height: size.height + 12)
        NSColor(white: 0.08, alpha: 0.8).setFill()
        NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
        text.draw(at: CGPoint(x: box.minX + 14, y: box.minY + 6), withAttributes: attributes)
    }

    // MARK: Input

    override func cursorUpdate(with event: NSEvent) {
        (isWindowMode ? NSCursor.pointingHand : NSCursor.crosshair).set()
    }

    override func mouseMoved(with event: NSEvent) {
        guard isWindowMode else { return }
        let point = convert(event.locationInWindow, from: nil)
        let hovered = windows.first { localRect(for: $0.frame).contains(point) }
        if hovered?.frame != hoveredWindow?.frame {
            hoveredWindow = hovered
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard !isWindowMode else { return }
        dragStart = convert(event.locationInWindow, from: nil)
        selection = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isWindowMode, let start = dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x), height: abs(point.y - start.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if isWindowMode {
            guard let window = hoveredWindow else { return }
            onFinish?(RegionPick(rect: window.frame, kind: .window, window: window))
            return
        }
        defer { dragStart = nil }
        guard let selection, selection.width >= 4, selection.height >= 4 else {
            self.selection = nil
            needsDisplay = true
            return
        }
        let global = selection.offsetBy(dx: screenOrigin.x, dy: screenOrigin.y)
        let center = CGPoint(x: global.midX, y: global.midY)
        onFinish?(RegionPick(rect: global, kind: .region, window: windows.first { $0.frame.contains(center) }))
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Escape:
            onFinish?(nil)
        case kVK_Space:
            isWindowMode.toggle()
            selection = nil
            dragStart = nil
            hoveredWindow = isWindowMode ? windowUnderMouse() : nil
            cursorUpdate(with: event)
            needsDisplay = true
        default:
            break
        }
    }

    private func windowUnderMouse() -> ScreenWindow? {
        guard let window else { return nil }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return windows.first { localRect(for: $0.frame).contains(point) }
    }

    private func localRect(for globalRect: CGRect) -> CGRect {
        globalRect.offsetBy(dx: -screenOrigin.x, dy: -screenOrigin.y)
    }
}
