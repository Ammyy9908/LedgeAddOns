// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppleMusicControls",
    platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/Ammyy9908/LedgeKit.git", exact: "0.8.0")],
    targets: [
        .target(name: "AppleMusicCore", dependencies: ["LedgeKit"]),
        .executableTarget(name: "AppleMusicControls", dependencies: ["LedgeKit", "AppleMusicCore"]),
        .testTarget(name: "AppleMusicTests", dependencies: ["AppleMusicCore", "LedgeKit"])
    ]
)
