import Foundation
import ClipbackCore

/// Reads each library's `people.json`. The file is the source of truth and can be edited by hand.
@MainActor
enum PeopleStore {
    static func url(for library: Library) -> URL {
        Vault.folder(for: library).appending(path: "people.json")
    }

    static func people(in library: Library) -> [Person] {
        guard let data = try? Data(contentsOf: url(for: library)) else { return [] }
        do {
            return try JSONDecoder().decode([Person].self, from: data)
        } catch {
            Log.store.error("Couldn't read people.json for \(library.title, privacy: .public): \(error, privacy: .public)")
            return []
        }
    }

    /// Recently used handles first, then the rest of the directory in its saved order.
    static func autocompletePool(for library: Library, recentHandles: [String]) -> [Person] {
        let directory = people(in: library)
        let byHandle = Dictionary(directory.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let recent = recentHandles.map { byHandle[$0.lowercased()] ?? Person(handle: $0, name: $0) }
        let recentIDs = Set(recent.map(\.id))
        return recent + directory.filter { !recentIDs.contains($0.id) }
    }
}
