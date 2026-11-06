import AppKit
import ClipbackCore
import Observation

/// A clip and where it lives on disk.
struct StoredClip: Identifiable, Sendable, Equatable {
    var clip: Clip
    var url: URL

    var id: String { url.path }

    var imageURL: URL? {
        clip.image.map { url.deletingLastPathComponent().appending(path: $0) }
    }
}

/// Every clip in both libraries, read from the vault into memory and kept fresh as files change.
/// The review window shows one library at a time; the menubar counts both.
@MainActor
@Observable
final class ClipLibrary {
    static let shared = ClipLibrary()

    private(set) var byLibrary: [Library: [StoredClip]] = [:] {
        didSet { activeByLibrary = byLibrary.mapValues { $0.filter { !$0.clip.isArchived } } }
    }
    /// Split out once per change rather than on every render, since most views show only active clips.
    private(set) var activeByLibrary: [Library: [StoredClip]] = [:]
    /// The library the review window is showing.
    var library: Library = AppSettings.shared.captureLibrary()

    /// Called after every reload, e.g. to refresh the menubar count.
    @ObservationIgnored var onReload: (() -> Void)?
    @ObservationIgnored private var watcher: VaultWatcher?
    @ObservationIgnored private var loadGeneration = 0

    private init() {}

    var clips: [StoredClip] { byLibrary[library] ?? [] }

    /// Clips still in play: everything except archived ones (put away, discussed, done or retired).
    var activeClips: [StoredClip] { activeClips(in: library) }

    func activeClips(in library: Library) -> [StoredClip] { activeByLibrary[library] ?? [] }

    var archivedCount: Int { clips.count - activeClips.count }

    /// Archived clips, most recently archived first. Archive dates are whole days, so clips archived the same day
    /// fall back to newest captured first, which keeps the order steady across reloads.
    var archivedClips: [StoredClip] {
        clips.filter(\.clip.isArchived).sorted {
            let (left, right) = ($0.clip, $1.clip)
            let (leftDay, rightDay) = (left.archivedOn ?? left.created, right.archivedOn ?? right.created)
            return leftDay != rightDay ? leftDay > rightDay : left.created > right.created
        }
    }

    /// The last clips that were archived, so the window can offer Undo. Keeps each clip as it was before, so Undo
    /// puts back exactly that, review schedule included.
    struct ArchiveEvent: Equatable {
        var before: [StoredClip]
        var title: String
        var at: Date
    }

    private(set) var lastArchived: ArchiveEvent?

    func clips(in library: Library) -> [StoredClip] { byLibrary[library] ?? [] }

    func start() {
        guard watcher == nil else { return }
        watcher = VaultWatcher(path: AppSettings.shared.vaultURL.path) { [weak self] in self?.reload() }
        reload()
    }

    func reload() {
        loadGeneration += 1
        let generation = loadGeneration
        let folders = Library.allCases.map { ($0, Vault.folder(for: $0)) }
        Task {
            let loaded = await Task.detached(priority: .userInitiated) {
                Dictionary(uniqueKeysWithValues: folders.map { ($0.0, Self.readClips(in: $0.1)) })
            }.value
            guard generation == loadGeneration else { return }
            byLibrary = loaded
            onReload?()
        }
    }

    /// Revise clips due in Today for a library.
    func today(in library: Library, now: Date = Date()) -> ReviewQueue.Today<StoredClip> {
        ReviewQueue.today(activeClips(in: library), clip: \.clip, now: now)
    }

    func answer(_ stored: StoredClip, _ answer: ReviewAnswer) {
        update(stored) { clip in
            let state = clip.review ?? ReviewState.initial(after: clip.created)
            clip.review = ReviewScheduler.apply(answer, to: state, today: Date())
        }
        if answer == .retire { noteArchived([stored]) }
    }

    /// Ticking a call as discussed or a to-do as done archives it, since it's finished with. Several at once
    /// share a single Undo.
    func markDone(_ list: [StoredClip]) {
        update(list) { _, clip in clip.done = Date() }
        noteArchived(list)
    }

    func archive(_ stored: StoredClip) {
        update(stored) { $0.archived = Date() }
        noteArchived([stored])
    }

    /// Brings clips back fully active, e.g. onto the call agenda again.
    func unarchive(ids: [StoredClip.ID]) {
        let wanted = Set(ids)
        update(byLibrary.values.joined().filter { wanted.contains($0.id) }) { _, clip in clip.unarchive() }
        if let event = lastArchived, Set(event.before.map(\.id)).isSubset(of: wanted) { lastArchived = nil }
    }

    /// Puts the clips from an archive event back exactly as they were.
    func undo(_ event: ArchiveEvent) {
        let before = Dictionary(event.before.map { ($0.id, $0.clip) }, uniquingKeysWith: { first, _ in first })
        update(byLibrary.values.joined().filter { before[$0.id] != nil }) { stored, clip in
            guard let old = before[stored.id] else { return }
            clip.archived = old.archived
            clip.done = old.done
            clip.review = old.review
        }
        if lastArchived == event { lastArchived = nil }
    }

    func clearArchiveEvent() {
        lastArchived = nil
    }

    private func noteArchived(_ stored: [StoredClip]) {
        guard let first = stored.first else { return }
        let title = stored.count == 1 ? (first.clip.title.isEmpty ? "Clip" : first.clip.title) : "\(stored.count) clips"
        lastArchived = ArchiveEvent(before: stored, title: title, at: Date())
    }

    /// Rewrites a clip's markdown after a change made in the review window.
    func update(_ stored: StoredClip, _ change: (inout Clip) -> Void) {
        update([stored]) { _, clip in change(&clip) }
    }

    /// Rewrites several clips, then refreshes the window and menubar once however many there are.
    func update(_ list: [StoredClip], _ change: (StoredClip, inout Clip) -> Void) {
        guard !list.isEmpty else { return }
        var updated = byLibrary
        for stored in list {
            var clip = stored.clip
            change(stored, &clip)
            do {
                try Data(ClipMarkdown.render(clip).utf8).write(to: stored.url, options: .atomic)
                if let index = updated[clip.library]?.firstIndex(where: { $0.id == stored.id }) {
                    updated[clip.library]?[index].clip = clip
                }
            } catch {
                Log.store.error("Updating clip failed: \(error, privacy: .public)")
            }
        }
        byLibrary = updated
        onReload?()
    }

    /// Moves a clip's markdown and image into the other library's folder, keeping the year/month layout.
    @discardableResult
    func move(_ stored: StoredClip, to target: Library) -> Bool {
        let from = Vault.folder(for: stored.clip.library).standardizedFileURL.path
        let path = stored.url.standardizedFileURL.path
        let relative = path.hasPrefix(from + "/") ? String(path.dropFirst(from.count + 1)) : stored.url.lastPathComponent
        let fileManager = FileManager.default
        var destination = Vault.folder(for: target).appending(path: relative)
        var counter = 2
        while fileManager.fileExists(atPath: destination.path) {
            let base = stored.url.deletingPathExtension().lastPathComponent
            destination = destination.deletingLastPathComponent().appending(path: "\(base)-\(counter).md")
            counter += 1
        }

        var clip = stored.clip
        clip.library = target
        do {
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let image = stored.imageURL, fileManager.fileExists(atPath: image.path) {
                let newImage = destination.deletingPathExtension().appendingPathExtension(image.pathExtension)
                try fileManager.moveItem(at: image, to: newImage)
                clip.image = newImage.lastPathComponent
            }
            try Data(ClipMarkdown.render(clip).utf8).write(to: destination, options: .atomic)
            try fileManager.removeItem(at: stored.url)
        } catch {
            Log.store.error("Moving clip failed: \(error, privacy: .public)")
            Toast.shared.show("Couldn't move the clip: \(error.localizedDescription)")
            return false
        }
        Log.store.info("Moved clip to \(target.title, privacy: .public): \(destination.path(percentEncoded: false), privacy: .public)")
        byLibrary[stored.clip.library]?.removeAll { $0.id == stored.id }
        byLibrary[target, default: []].insert(StoredClip(clip: clip, url: destination), at: 0)
        byLibrary[target]?.sort { $0.clip.created > $1.clip.created }
        onReload?()
        return true
    }

    /// Moves the markdown file and its image to the Trash, so a mistake can be undone from Finder.
    func delete(_ stored: StoredClip) {
        let urls = [stored.url] + (stored.imageURL.map { [$0] } ?? [])
        NSWorkspace.shared.recycle(urls) { _, error in
            if let error {
                Log.store.error("Deleting clip failed: \(error, privacy: .public)")
            } else {
                Log.store.info("Moved clip to Trash: \(stored.url.path(percentEncoded: false), privacy: .public)")
            }
        }
        byLibrary[stored.clip.library]?.removeAll { $0.id == stored.id }
        onReload?()
    }

    nonisolated private static func readClips(in folder: URL) -> [StoredClip] {
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil,
                                                              options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var result: [StoredClip] = []
        for case let url as URL in enumerator where url.pathExtension == "md" {
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  let clip = ClipParser.parse(text) else { continue }
            result.append(StoredClip(clip: clip, url: url))
        }
        return result.sorted { $0.clip.created > $1.clip.created }
    }
}

/// Calls back on the main thread, at most every half second, when anything under the vault changes,
/// including edits made outside Clipback. The stream is delivered on the main queue, so the callback is main-isolated.
final class VaultWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let onChange: @MainActor () -> Void

    init(path: String, onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<VaultWatcher>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { watcher.onChange() }
        }
        stream = FSEventStreamCreate(nil, callback, &context, [path] as CFArray,
                                     FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5,
                                     FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            FSEventStreamStart(stream)
        }
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
