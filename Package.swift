// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacSpeedMonitor",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "SpeedMonitorCore", targets: ["SpeedMonitorCore"]),
        .executable(name: "MacSpeedMonitor", targets: ["MacSpeedMonitorApp"]),
    ],
    targets: [
        .target(
            name: "SpeedMonitorCore",
            path: "Sources/SpeedMonitorCore"
        ),
        .executableTarget(
            name: "MacSpeedMonitorApp",
            dependencies: ["SpeedMonitorCore"],
            path: "Sources/MacSpeedMonitorApp"
        ),
    ]
)
