import Foundation

/// Someone you can raise things with on a call. Stored per library in `people.json` so it stays editable by hand.
public struct Person: Codable, Sendable, Equatable, Identifiable {
    /// What you type after `@`. One word, unique within a library.
    public var handle: String
    public var name: String
    public var title: String?

    public var id: String { handle.lowercased() }

    public init(handle: String, name: String, title: String? = nil) {
        self.handle = handle
        self.name = name
        self.title = title
    }
}

public enum PeopleDirectory {
    /// Handles are first names, or the full name in CamelCase when a first name is shared.
    public static func handles(for names: [String]) -> [String] {
        let firstNames = names.map { words(in: $0).first ?? $0 }
        var counts: [String: Int] = [:]
        for first in firstNames { counts[first.lowercased(), default: 0] += 1 }
        return zip(names, firstNames).map { name, first in
            counts[first.lowercased(), default: 0] > 1 ? words(in: name).joined() : first
        }
    }

    /// People whose handle or any part of their name starts with what's been typed, best matches first.
    public static func matches(_ partial: String, in people: [Person], limit: Int = 4) -> [Person] {
        let query = partial.lowercased()
        guard !query.isEmpty else { return Array(people.prefix(limit)) }
        let handleHits = people.filter { $0.handle.lowercased().hasPrefix(query) && $0.handle.lowercased() != query }
        let nameHits = people.filter { person in
            !handleHits.contains(person)
                && person.handle.lowercased() != query
                && person.name.lowercased().split(separator: " ").contains { $0.hasPrefix(query) }
        }
        return Array((handleHits + nameHits).prefix(limit))
    }

    private static func words(in name: String) -> [String] {
        name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { $0.prefix(1).uppercased() + $0.dropFirst() }
    }
}
