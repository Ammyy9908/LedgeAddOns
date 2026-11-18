// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Lyrics", platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/Ammyy9908/LedgeKit.git", exact: "0.22.0")],
    targets: [
        .target(name: "LyricsCore"),
        .executableTarget(name: "Lyrics", dependencies: ["LyricsCore", "LedgeKit"]),
        .testTarget(name: "LyricsTests", dependencies: ["LyricsCore"])
    ])
