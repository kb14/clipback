import Foundation
import ClipbackCore

/// The folder of markdown clips on disk. One subfolder per library.
@MainActor
enum Vault {
    static func folder(for library: Library) -> URL {
        AppSettings.shared.vaultURL.appendingPathComponent(library.title, isDirectory: true)
    }

    static func bootstrap() {
        for library in Library.allCases {
            try? FileManager.default.createDirectory(at: folder(for: library), withIntermediateDirectories: true)
        }
    }
}
