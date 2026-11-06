import Foundation

/// Tidies text read from other apps before it's stored.
public enum TextCleaner {
    /// Object replacement (inline images and attachments), zero-width spaces and byte order marks.
    private static let invisible: Set<Character> = ["\u{FFFC}", "\u{200B}", "\u{FEFF}"]

    public static func clean(_ text: String) -> String {
        String(text.filter { !invisible.contains($0) })
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
