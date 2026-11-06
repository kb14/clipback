import ClipbackCore
import SwiftUI

/// The app's colours, shared by every view.
extension Intent {
    var color: Color {
        switch self {
        case .save: Color(red: 0.56, green: 0.56, blue: 0.58)
        case .revise: Color(red: 0.49, green: 0.36, blue: 0.84)
        case .call: Color(red: 0.09, green: 0.58, blue: 0.42)
        case .todo: Color(red: 0.76, green: 0.48, blue: 0.05)
        }
    }
}

extension Library {
    var color: Color {
        switch self {
        case .personal: Color(red: 0.88, green: 0.44, blue: 0.17)
        case .work: Color(red: 0.18, green: 0.44, blue: 0.87)
        }
    }
}

extension Color {
    static let highlight = Color(red: 1, green: 0.8, blue: 0).opacity(0.55)
}

/// Blurs whatever is behind a borderless panel, like Spotlight.
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
