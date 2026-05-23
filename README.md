# MacSpeedMonitor

A minimal SwiftUI network speed monitor with shared core code for macOS and iOS.

## What is in this package
- `SpeedMonitorCore` (library): reusable monitor + UI.
- `MacSpeedMonitor` (executable): macOS app entry point for `swift run`.
- `iOSSpeedMonitorApp` (target): iOS app entry point source for Xcode-based app bundling.

The UI shows:
- Download speed
- Upload speed

## Run (macOS)

```bash
cd "/Users/adisapir/Library/CloudStorage/OneDrive-Personal/Projects/Codex/SimpleSpeedMonitor"
swift run
```

## Build (macOS)

```bash
cd "/Users/adisapir/Library/CloudStorage/OneDrive-Personal/Projects/Codex/SimpleSpeedMonitor"
swift build
```

## iOS setup (Xcode)
1. Open the package in Xcode.
2. Add a new iOS App target in an Xcode project/workspace.
3. Link `SpeedMonitorCore` to the iOS app target.
4. Use `Sources/iOSSpeedMonitorApp/iOSSpeedMonitorApp.swift` as the app entry point source.
5. Select an iOS simulator/device and run.

Note: SwiftPM in this repository provides shared code and target structure; iOS deployment still requires an app bundle target configured in Xcode (signing, provisioning, Info.plist).

## Clean rebuild
```bash
swift package clean
rm -rf .build
swift build
```

The app polls network interface counters every second and displays throughput in `/s`.
