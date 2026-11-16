// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Emoji",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../../../LedgeKit")],
    targets: [
        // What the add-on knows and what it shows, testable without Ledge.
        .target(name: "EmojiCore", dependencies: [.product(name: "LedgeKit", package: "LedgeKit")]),
        // The program Ledge runs: a session that sends what Core builds.
        .executableTarget(name: "Emoji", dependencies: ["EmojiCore", .product(name: "LedgeKit", package: "LedgeKit")]),
        .testTarget(name: "EmojiTests", dependencies: ["EmojiCore", .product(name: "LedgeKit", package: "LedgeKit")]),
    ]
)
