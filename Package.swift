// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacSpeedMonitor",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "SpeedMonitorCore", targets: ["SpeedMonitorCore"]),
        .executable(name: "MacSpeedMonitor", targets: ["MacSpeedMonitorApp"]),
    ],
    targets: [
        .target(
            name: "SpeedMonitorCore",
            path: "Sources/SpeedMonitorCore",
            resources: [
                .process("Resources/oui-vendors.tsv"),
            ],
            linkerSettings: [
                .linkedFramework("Security"),
            ]
        ),
        .executableTarget(
            name: "MacSpeedMonitorApp",
            dependencies: ["SpeedMonitorCore"],
            path: "Sources/MacSpeedMonitorApp",
            exclude: ["Info.plist", "MacSpeedMonitor.entitlements"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/MacSpeedMonitorApp/Info.plist",
                ])
            ]
        ),
        .testTarget(
            name: "SpeedMonitorCoreTests",
            dependencies: ["SpeedMonitorCore"],
            path: "Tests/SpeedMonitorCoreTests"
        ),
    ]
)
