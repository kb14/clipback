import os

/// Read with: log stream --predicate 'subsystem == "io.github.kb14.clipback"' --level debug
enum Log {
    static let capture = Logger(subsystem: "io.github.kb14.clipback", category: "capture")
    static let store = Logger(subsystem: "io.github.kb14.clipback", category: "store")
}
