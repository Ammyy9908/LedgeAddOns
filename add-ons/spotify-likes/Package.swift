// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpotifyLikes",
    platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/Ammyy9908/LedgeKit.git", exact: "0.7.0")],
    targets: [
        .target(name: "SpotifyLikesCore", dependencies: ["LedgeKit"]),
        .executableTarget(name: "SpotifyLikes", dependencies: ["LedgeKit", "SpotifyLikesCore"]),
        .testTarget(name: "SpotifyLikesTests", dependencies: ["SpotifyLikesCore", "LedgeKit"])
    ]
)
