import Foundation
import ClipbackCore

/// Writes clips into the vault as markdown files, and remembers recent people and tags for autocomplete.
@MainActor
enum ClipStore {
    private static let recentLimit = 50

    /// The image, if any, is written beside the markdown file with the same name.
    @discardableResult
    static func save(_ clip: Clip, image: EncodedImage? = nil) throws -> URL {
        var clip = clip
        let target = Vault.folder(for: clip.library).appending(path: ClipMarkdown.relativePath(for: clip))
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let url = uniqueURL(for: target)
        if let image {
            let imageURL = url.deletingPathExtension().appendingPathExtension(image.fileExtension)
            try image.data.write(to: imageURL, options: .atomic)
            clip.image = imageURL.lastPathComponent
        }
        try Data(ClipMarkdown.render(clip).utf8).write(to: url, options: .atomic)
        remember(NoteParser.people(in: clip.note), key: Keys.people)
        remember(clip.tags, key: Keys.tags)
        return url
    }

    static var recentPeople: [String] { UserDefaults.clipback.stringArray(forKey: Keys.people) ?? [] }
    static var recentTags: [String] { UserDefaults.clipback.stringArray(forKey: Keys.tags) ?? [] }

    /// Two clips in the same minute with the same title get `-2`, `-3` and so on.
    private static func uniqueURL(for url: URL) -> URL {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent
        let folder = url.deletingLastPathComponent()
        var counter = 2
        while true {
            let candidate = folder.appending(path: "\(base)-\(counter).md")
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }

    private static func remember(_ values: [String], key: String) {
        guard !values.isEmpty else { return }
        let lowered = Set(values.map { $0.lowercased() })
        let existing = UserDefaults.clipback.stringArray(forKey: key) ?? []
        let merged = values + existing.filter { !lowered.contains($0.lowercased()) }
        UserDefaults.clipback.set(Array(merged.prefix(recentLimit)), forKey: key)
    }

    private enum Keys {
        static let people = "recentPeople"
        static let tags = "recentTags"
    }
}
