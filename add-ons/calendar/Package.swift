// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Calendar",
    platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/Ammyy9908/LedgeKit.git", exact: "0.27.0")],
    targets: [
        // Which events show, the countdown, meeting links and what each surface draws, testable without Ledge.
        .target(name: "CalendarCore", dependencies: [.product(name: "LedgeKit", package: "LedgeKit")]),
        // The program Ledge runs: reads the calendars with EventKit and sends what Core builds.
        .executableTarget(name: "Calendar", dependencies: ["CalendarCore", .product(name: "LedgeKit", package: "LedgeKit")]),
        .testTarget(name: "CalendarTests", dependencies: ["CalendarCore", .product(name: "LedgeKit", package: "LedgeKit")]),
    ]
)
