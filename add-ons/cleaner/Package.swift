// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Cleaner", platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/Ammyy9908/LedgeKit.git", exact: "0.22.0")],
    targets: [
        .target(name: "CleanerCore"),
        .executableTarget(name: "Cleaner", dependencies: ["CleanerCore", "LedgeKit"]),
        .testTarget(name: "CleanerTests", dependencies: ["CleanerCore"])
    ])
