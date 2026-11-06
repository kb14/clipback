import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let capture = Self("capture", default: .init(.space, modifiers: [.control, .option]))
    static let openClipback = Self("openClipback", default: .init(.n, modifiers: [.control, .option]))
}

@MainActor
enum Hotkeys {
    static func register(onCapture: @escaping @MainActor () -> Void, onOpenClipback: @escaping @MainActor () -> Void) {
        KeyboardShortcuts.onKeyDown(for: .capture) { onCapture() }
        KeyboardShortcuts.onKeyDown(for: .openClipback) { onOpenClipback() }
    }

    /// The capture shortcut as macOS menus show it, such as ⌃⌥Space. Nil if it was cleared in Settings.
    static var captureTitle: String? { KeyboardShortcuts.getShortcut(for: .capture)?.description }
}
