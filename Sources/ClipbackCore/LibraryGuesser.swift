import Foundation

/// Pre-picks Work or Personal for a new clip from where it came from. The user can flip it in the panel.
public struct LibraryGuesser: Sendable {
    /// What always means Work, from Settings: an app's name or bundle id, or a word found in the page address,
    /// window title or file path (e.g. a company domain).
    public var workRules: [String]

    public init(workRules: [String]) {
        self.workRules = workRules.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
    }

    public func guess(for source: ClipSource, fallback: Library) -> Library {
        let app = [source.app.lowercased(), source.bundleID?.lowercased()].compactMap { $0 }
        if workRules.contains(where: app.contains) { return .work }
        let haystack = [source.url, source.window, source.file].compactMap { $0 }.joined(separator: " ").lowercased()
        if workRules.contains(where: haystack.contains) { return .work }
        return fallback
    }
}
