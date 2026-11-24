// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Agents", platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/Ammyy9908/LedgeKit.git", exact: "0.27.0")],
    targets: [
        .target(name: "AgentsCore"),
        .executableTarget(name: "Agents", dependencies: ["AgentsCore", "LedgeKit"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "AgentsTests", dependencies: ["AgentsCore"])
    ])
