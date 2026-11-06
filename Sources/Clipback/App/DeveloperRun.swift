import Foundation

/// A launch by a developer tool (UI snapshots, made-up test clips, the screen-share and permission checks)
/// rather than for real use. Such a run saves into a scratch copy of the settings, so nothing it changes reaches
/// the user's own. Debug builds only; a Release build is never a developer run.
enum DeveloperRun {
    /// Every flag a developer tool launches Clipback with.
    private static let flags = ["--vault", "--fixtures", "--showcase", "--ui-snapshots", "--appearance", "--share-test",
                                "--request-screen-recording"]

    static let isActive: Bool = {
        #if DEBUG
        CommandLine.arguments.contains(where: flags.contains)
        #else
        false
        #endif
    }()

    /// The value given after a flag, e.g. the folder after `--vault`.
    static func value(after flag: String) -> String? {
        guard isActive, let index = CommandLine.arguments.firstIndex(of: flag),
              CommandLine.arguments.indices.contains(index + 1) else { return nil }
        return CommandLine.arguments[index + 1]
    }

    private static let scratchSuite = "io.github.kb14.clipback.developer-run"

    /// A fresh copy of the user's settings for this run, so screens look the way they do day to day.
    fileprivate static func scratchDefaults() -> UserDefaults {
        guard let scratch = UserDefaults(suiteName: scratchSuite) else { return .standard }
        let own = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) } ?? [:]
        scratch.setPersistentDomain(own, forName: scratchSuite)
        return scratch
    }
}

extension UserDefaults {
    /// Where Clipback keeps its settings: the user's own, or a scratch copy of them during a developer run.
    /// macOS saves window sizes in `.standard` regardless, so `WindowManager` skips that during a developer run.
    /// UserDefaults is thread-safe (Apple documents it so), it just isn't marked Sendable.
    nonisolated(unsafe) static let clipback: UserDefaults = DeveloperRun.isActive ? DeveloperRun.scratchDefaults() : .standard
}
