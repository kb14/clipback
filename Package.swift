// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Clipback",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        // Pure logic with no AppKit: the clip model, markdown format and note parsing. Unit tested.
        .target(
            name: "ClipbackCore",
            path: "Sources/ClipbackCore"
        ),
        .executableTarget(
            name: "Clipback",
            dependencies: ["ClipbackCore", "KeyboardShortcuts"],
            path: "Sources/Clipback"
        ),
        .testTarget(
            name: "ClipbackCoreTests",
            dependencies: ["ClipbackCore"],
            path: "Tests/ClipbackCoreTests"
        ),
    ]
)
