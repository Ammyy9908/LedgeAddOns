// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuickTranslate",
    platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/Ammyy9908/LedgeKit.git", exact: "0.24.0")],
    targets: [
        // What the add-on knows and what it shows, testable without Ledge.
        .target(name: "QuickTranslateCore", dependencies: [.product(name: "LedgeKit", package: "LedgeKit")]),
        // The program Ledge runs: a session that sends what Core builds.
        .executableTarget(name: "QuickTranslate", dependencies: ["QuickTranslateCore", .product(name: "LedgeKit", package: "LedgeKit")]),
        .testTarget(name: "QuickTranslateTests", dependencies: ["QuickTranslateCore", .product(name: "LedgeKit", package: "LedgeKit")]),
    ]
)
