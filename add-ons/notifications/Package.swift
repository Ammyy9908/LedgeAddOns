// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Notifications", platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/Ammyy9908/LedgeKit.git", exact: "0.2.0")],
    targets: [
        .target(name: "NotificationsCore", dependencies: ["LedgeKit"]),
        .executableTarget(name: "Notifications", dependencies: ["NotificationsCore"]),
        .testTarget(name: "NotificationsTests", dependencies: ["NotificationsCore", "LedgeKit"])
    ])
