import SwiftUI

/// What a view shows when it has nothing in it: what the view is for and how to fill it.
struct EmptyState {
    var title: String
    var symbol: String
    var message: String

    static let inbox = EmptyState(title: "No clips yet", symbol: "tray",
        message: "Select text in any app and press ⌃⌥Space. Press it with nothing selected to clip part of the screen instead.")
    static let revise = EmptyState(title: "Nothing to revise", symbol: "repeat",
        message: "Mark a clip Revise (⌘2 when capturing). It comes back in Today tomorrow, then after 3, 7, 16, 35 and 75 days.")
    static let todo = EmptyState(title: "No to-dos", symbol: "checkmark.square",
        message: "Mark a clip To-do (⌘4 when capturing) to park something you need to act on.")
    static let calls = EmptyState(title: "No one to call", symbol: "phone",
        message: "Mark a clip Call (⌘3) or write @name in its note to collect things to raise with someone.")
    static let callsDiscussed = EmptyState(title: "All discussed", symbol: "checkmark.circle",
        message: "Discussed calls are in Archive. Mark a clip Call (⌘3) or write @name in its note to add more.")
    static let sources = EmptyState(title: "No sources yet", symbol: "link",
        message: "Clips from web pages and files are grouped here, so everything from one article sits together.")
    static let archive = EmptyState(title: "Nothing archived", symbol: "archivebox",
        message: "Discussed calls, finished to-dos, retired Revise clips and anything you archive end up here, out of the way but still searchable.")
    static let none = EmptyState(title: "No clips here", symbol: "tray", message: "")

    static func search(_ query: String) -> EmptyState {
        EmptyState(title: "No results for “\(query)”", symbol: "magnifyingglass",
                   message: "Search looks through titles, notes, clipped text, text in screenshots, tags, people and sources.")
    }
}

struct EmptyStateView: View {
    let state: EmptyState

    var body: some View {
        ContentUnavailableView {
            Label(state.title, systemImage: state.symbol)
        } description: {
            if !state.message.isEmpty {
                Text(state.message).frame(maxWidth: 380)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
