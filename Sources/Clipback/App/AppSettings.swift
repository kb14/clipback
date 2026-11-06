import AppKit
import ClipbackCore
import Observation

enum CaptureMode: String, CaseIterable {
    case automatic
    case personal
    case work
}

/// Light or dark for Clipback's own windows and panels. System follows the macOS setting.
enum Appearance: String, CaseIterable {
    case system
    case light
    case dark

    var title: String {
        switch self {
        case .system: "Match System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

/// User preferences that outlive a launch, in `UserDefaults.clipback`.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.clipback

    nonisolated static var defaultVaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Clipback", isDirectory: true)
    }

    var vaultURL: URL {
        didSet { defaults.set(vaultURL.path, forKey: Keys.vaultPath) }
    }

    /// Which library new clips start in. Automatic follows work hours; the capture panel can still flip it.
    var captureMode: CaptureMode {
        didSet { defaults.set(captureMode.rawValue, forKey: Keys.captureMode) }
    }

    /// The library a capture starts in right now.
    func captureLibrary(at date: Date = Date()) -> Library {
        switch captureMode {
        case .automatic: WorkHours.standard.library(at: date)
        case .personal: .personal
        case .work: .work
        }
    }

    var isPaused: Bool {
        didSet { defaults.set(isPaused, forKey: Keys.paused) }
    }

    /// Apps, or words in a page address, window title or file path, whose clips always start in Work, whatever
    /// the capture mode. Empty until the user adds some.
    var workRules: [String] {
        didSet { defaults.set(workRules, forKey: Keys.workRules) }
    }

    var appearance: Appearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: Keys.appearance)
            applyAppearance()
        }
    }

    /// Every window and panel follows the app's appearance, so setting it once covers them all.
    func applyAppearance() {
        NSApplication.shared.appearance = switch appearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    private init() {
        // A saved folder that no longer exists (deleted, or an unplugged drive) falls back to ~/Clipback for this
        // launch rather than showing an empty library. The saved choice is left alone.
        let saved = defaults.string(forKey: Keys.vaultPath).map { URL(fileURLWithPath: $0, isDirectory: true) }
        if let saved, FileManager.default.fileExists(atPath: saved.path) {
            vaultURL = saved
        } else {
            vaultURL = Self.defaultVaultURL
        }
        captureMode = defaults.string(forKey: Keys.captureMode).flatMap(CaptureMode.init(rawValue:)) ?? .automatic
        isPaused = defaults.bool(forKey: Keys.paused)
        workRules = defaults.stringArray(forKey: Keys.workRules) ?? []
        appearance = defaults.string(forKey: Keys.appearance).flatMap(Appearance.init(rawValue:)) ?? .system
        // Developer tools point a run at a throwaway vault, or render in light or dark. These are saved only into
        // the run's scratch settings.
        if let vault = DeveloperRun.value(after: "--vault") {
            vaultURL = URL(fileURLWithPath: vault, isDirectory: true)
        }
        if let forced = DeveloperRun.value(after: "--appearance").flatMap(Appearance.init(rawValue:)) {
            appearance = forced
        }
    }

    private enum Keys {
        static let vaultPath = "vaultPath"
        static let captureMode = "captureMode"
        static let paused = "paused"
        static let workRules = "workRules"
        static let appearance = "appearance"
    }
}
