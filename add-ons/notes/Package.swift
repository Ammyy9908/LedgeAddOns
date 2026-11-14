// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Notes", platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/Ammyy9908/LedgeKit.git", exact: "0.16.0")],
    targets: [
        .target(name: "NotesCore"),
        .executableTarget(name: "Notes", dependencies: ["NotesCore", "LedgeKit"]),
        .testTarget(name: "NotesTests", dependencies: ["NotesCore"])
    ])
