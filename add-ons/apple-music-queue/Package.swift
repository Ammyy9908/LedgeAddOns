// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "AppleMusicQueue", platforms: [.macOS(.v14)],
    products: [.library(name: "QueueBridge", type: .dynamic, targets: ["QueueBridge"])],
    dependencies: [.package(url: "https://github.com/Ammyy9908/LedgeKit.git", exact: "0.2.0")],
    targets: [
        .target(name: "QueueBridge", linkerSettings: [.linkedFramework("Foundation")]),
        .executableTarget(name: "AppleMusicQueue", dependencies: ["QueueBridge", "LedgeKit"]),
        // Compiles QueueBridge.m into its own unit, so it must not also link the QueueBridge target.
        .testTarget(name: "QueueBridgeTests", path: "Tests/QueueBridgeTests",
                    cSettings: [.headerSearchPath("../../Sources/QueueBridge/include")])
    ])
