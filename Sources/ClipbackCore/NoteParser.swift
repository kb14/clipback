import Foundation

extension Clip {
    /// Everyone this clip is for: its person plus anyone else @mentioned in the note, without duplicates.
    public var people: [String] {
        var names = person.map { [$0] } ?? []
        for name in NoteParser.people(in: note) where !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            names.append(name)
        }
        return names
    }
}

/// Reads `@person` and `#tag` out of the single note field in the capture panel.
public enum NoteParser {
    public struct Token: Equatable, Sendable {
        public var sigil: Character
        public var partial: String
    }

    /// People mentioned with `@`, first letter capitalised, in order, without duplicates.
    public static func people(in note: String) -> [String] {
        unique(note.matches(of: /@([\p{L}\p{N}_.\-]+)/).map { capitalizeFirst(trimPunctuation(String($0.output.1))) })
    }

    /// Tags written with `#`, lowercased, in order, without duplicates.
    public static func tags(in note: String) -> [String] {
        unique(note.matches(of: /(?:^|\s)#([\p{L}\p{N}_\-]+)/).map { String($0.output.1).lowercased() })
    }

    /// The note with `@person` and `#tag` words removed, for places that list people and tags separately.
    public static func withoutMentions(_ note: String) -> String {
        note.replacing(/(?:^|\s)[@#][\p{L}\p{N}_.\-]+/, with: "")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The note as a sentence for display. `#tags` are dropped. `@names` read as plain names where the sentence
    /// needs them ("pricing for @Maya" → "pricing for Maya"), but a trailing run of tags is dropped
    /// ("standup tomorrow @Maya @Leo" → "standup tomorrow"). Empty when the note was only tags.
    public static func readable(_ note: String) -> String {
        guard !withoutMentions(note).isEmpty else { return "" }
        var words = note.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.hasPrefix("#") }
        var trailing: [String] = []
        while let last = words.last, last.hasPrefix("@") {
            trailing.insert(last, at: 0)
            words.removeLast()
        }
        let linking: Set<String> = ["for", "with", "to", "from", "by", "ask", "tell", "ping", "cc", "and", "via"]
        if let before = words.last?.lowercased(), linking.contains(before) {
            words += trailing
        }
        return words.map { $0.hasPrefix("@") ? String($0.dropFirst()) : $0 }.joined(separator: " ")
    }

    /// The `@` or `#` word being typed at the end of the note, if any, for autocomplete.
    public static func trailingToken(in note: String) -> Token? {
        guard let match = note.firstMatch(of: /(?:^|\s)([@#])([\p{L}\p{N}_.\-]*)$/) else { return nil }
        return Token(sigil: Character(String(match.output.1)), partial: String(match.output.2))
    }

    /// Replaces the trailing `@` or `#` word with the chosen value and adds a space.
    public static func complete(_ note: String, with value: String) -> String {
        guard let token = trailingToken(in: note) else { return note }
        let kept = note.dropLast(token.partial.count + 1)
        return kept + String(token.sigil) + value + " "
    }

    private static func trimPunctuation(_ word: String) -> String {
        word.trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
    }

    private static func capitalizeFirst(_ word: String) -> String {
        word.prefix(1).uppercased() + word.dropFirst()
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
}
