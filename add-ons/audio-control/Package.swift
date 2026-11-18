// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "AudioControl", platforms: [.macOS("14.2")],
    dependencies: [.package(url: "https://github.com/Ammyy9908/LedgeKit.git", exact: "0.22.0")],
    targets: [
        .target(name: "AudioControlCore"),
        .executableTarget(name: "AudioControl", dependencies: ["AudioControlCore", "LedgeKit"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "AudioControlTests", dependencies: ["AudioControlCore"])
    ])
