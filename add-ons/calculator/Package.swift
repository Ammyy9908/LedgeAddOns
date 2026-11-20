// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Calculator",
    platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/Ammyy9908/LedgeKit.git", exact: "0.23.0")],
    targets: [
        // What the add-on knows and what it shows, testable without Ledge.
        .target(name: "CalculatorCore", dependencies: [.product(name: "LedgeKit", package: "LedgeKit")]),
        // The program Ledge runs: a session that sends what Core builds.
        .executableTarget(name: "Calculator", dependencies: ["CalculatorCore", .product(name: "LedgeKit", package: "LedgeKit")]),
        .testTarget(name: "CalculatorTests", dependencies: ["CalculatorCore", .product(name: "LedgeKit", package: "LedgeKit")]),
    ]
)
