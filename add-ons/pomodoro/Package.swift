// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pomodoro",
    platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/Ammyy9908/LedgeKit.git", exact: "0.25.0")],
    targets: [
        // The timer and what it shows, testable without Ledge.
        .target(name: "PomodoroCore", dependencies: [.product(name: "LedgeKit", package: "LedgeKit")]),
        // The program Ledge runs: a session that ticks the timer, plays sounds and sends what Core builds.
        .executableTarget(name: "Pomodoro", dependencies: ["PomodoroCore", .product(name: "LedgeKit", package: "LedgeKit")]),
        .testTarget(name: "PomodoroTests", dependencies: ["PomodoroCore", .product(name: "LedgeKit", package: "LedgeKit")]),
    ]
)
