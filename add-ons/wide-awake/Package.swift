// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WideAwake",
    platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/Ammyy9908/LedgeKit.git", exact: "0.26.0")],
    targets: [
        // When to stay awake and what it shows, testable without Ledge.
        .target(name: "WideAwakeCore", dependencies: [.product(name: "LedgeKit", package: "LedgeKit")]),
        // The program Ledge runs: holds the power assertion, watches the triggers and sends what Core builds.
        .executableTarget(name: "WideAwake", dependencies: ["WideAwakeCore", .product(name: "LedgeKit", package: "LedgeKit")]),
        .testTarget(name: "WideAwakeTests", dependencies: ["WideAwakeCore", .product(name: "LedgeKit", package: "LedgeKit")]),
    ]
)
