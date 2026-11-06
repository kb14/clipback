import ApplicationServices
import Foundation

/// Thin typed wrappers over the Accessibility C API.
enum AX {
    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    static func role(_ element: AXUIElement) -> String? {
        string(element, kAXRoleAttribute)
    }

    static func range(_ element: AXUIElement, _ attribute: String) -> CFRange? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    /// A window's frame from its position and size, in global top-left coordinates.
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = value(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = value(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    static func url(_ element: AXUIElement, _ attribute: String) -> String? {
        let raw = value(element, attribute)
        return (raw as? URL)?.absoluteString ?? (raw as? String)
    }

    static func setFlag(_ element: AXUIElement, _ attribute: String, _ flag: Bool) {
        AXUIElementSetAttributeValue(element, attribute as CFString, (flag ? kCFBooleanTrue : kCFBooleanFalse) as CFTypeRef)
    }

    /// Breadth-first search below `root`, bounded so a huge web page can't stall a capture.
    static func first(under root: AXUIElement, limit: Int = 600, where match: (AXUIElement) -> Bool) -> AXUIElement? {
        var queue = [root]
        var visited = 0
        while !queue.isEmpty, visited < limit {
            let element = queue.removeFirst()
            visited += 1
            if match(element) { return element }
            queue.append(contentsOf: children(element))
        }
        return nil
    }
}
