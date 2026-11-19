// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Launcher", platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/Ammyy9908/LedgeKit.git", exact: "0.22.0")],
    targets: [
        .target(name: "LauncherCore"),
        .executableTarget(name: "Launcher", dependencies: ["LauncherCore", "LedgeKit"]),
        .testTarget(name: "LauncherTests", dependencies: ["LauncherCore"])
    ])
