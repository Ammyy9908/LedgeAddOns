// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "LocalSend", platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/Ammyy9908/LedgeKit.git", exact: "0.20.0")],
    targets: [
        .target(name: "LocalSendCore"),
        .executableTarget(name: "LocalSend", dependencies: ["LocalSendCore", "LedgeKit"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "LocalSendTests", dependencies: ["LocalSendCore"])
    ])
