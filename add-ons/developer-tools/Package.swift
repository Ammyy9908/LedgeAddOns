// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DeveloperTools",
    platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/Ammyy9908/LedgeKit.git", exact: "0.24.0")],
    targets: [
        // What the add-on knows and what it shows, testable without Ledge.
        .target(name: "DeveloperToolsCore", dependencies: [.product(name: "LedgeKit", package: "LedgeKit")]),
        // The program Ledge runs: a session that sends what Core builds.
        .executableTarget(name: "DeveloperTools", dependencies: ["DeveloperToolsCore", .product(name: "LedgeKit", package: "LedgeKit")]),
        .testTarget(name: "DeveloperToolsTests", dependencies: ["DeveloperToolsCore", .product(name: "LedgeKit", package: "LedgeKit")]),
    ]
)
