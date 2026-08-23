// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ClockodoMenubar",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "ClockodoMenubar",
            targets: ["ClockodoMenubar"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "ClockodoMenubar",
            path: "Sources/ClockodoMenubar"
        ),
        .testTarget(
            name: "ClockodoMenubarTests",
            dependencies: ["ClockodoMenubar"],
            path: "Tests/ClockodoMenubarTests"
        ),
    ]
)
