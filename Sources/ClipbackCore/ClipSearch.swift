import Foundation

/// Plain in-memory search: every word of the query must appear somewhere in the clip.
/// Fast enough for thousands of clips; a database index can replace it if the vault ever gets huge.
public enum ClipSearch {
    public static func matches(_ clip: Clip, query: String) -> Bool {
        let words = normalize(query).split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let haystack = normalize(searchableText(of: clip))
        return words.allSatisfy { haystack.contains($0) }
    }

    public static func searchableText(of clip: Clip) -> String {
        let tags: String = clip.tags.map { "#" + $0 }.joined(separator: " ")
        let person: String = clip.person.map { "@" + $0 } ?? ""
        let optional: [String?] = [clip.ocr, clip.before, clip.after, clip.source.window, clip.source.url, clip.source.file]
        let parts: [String] = [clip.title, clip.selection, clip.note, tags, person, clip.source.app] + optional.compactMap { $0 }
        return parts.joined(separator: "\n")
    }

    /// Case and accent insensitive.
    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
