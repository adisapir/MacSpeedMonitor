# SimpleSpeedMonitor

A lightweight SwiftUI network speed monitor with a shared core library for macOS and iOS.

## Package Structure

| Target | Type | Description |
|---|---|---|
| `SpeedMonitorCore` | Library | Reusable monitor + SwiftUI UI, shared across platforms |
| `MacSpeedMonitorApp` | Executable | macOS app entry point (`swift run`) |
| `iOSSpeedMonitorApp` | Target | iOS app entry point source for Xcode-based bundling |

**Platform requirements:** macOS 13+, iOS 16+

## Features

- **Live throughput** — download and upload speed, updated every second
- **Session totals** — cumulative bytes downloaded and uploaded since monitoring started
- **Runtime counter** — elapsed time displayed as `MM:SS` or `HH:MM:SS`
- **Status reporting** — `idle`, `running`, `degraded`, or `stopped` states via `MonitorStatus`
- **Error recovery** — detects `getifaddrs` failures and interface counter resets; auto-recovers after transient errors
- **Configurable sampling interval** — defaults to 1 s, minimum 0.2 s

## Run (macOS)

```bash
cd /path/to/SimpleSpeedMonitor
swift run
```

## Build (macOS)

```bash
swift build
```

## iOS Setup (Xcode)

1. Open the package in Xcode.
2. Add a new iOS App target in an Xcode project/workspace.
3. Link `SpeedMonitorCore` to the iOS app target.
4. Use `Sources/iOSSpeedMonitorApp/iOSSpeedMonitorApp.swift` as the app entry point.
5. Select an iOS simulator or device and run.

> **Note:** SwiftPM provides shared code and target structure. iOS deployment still requires an app-bundle target in Xcode (signing, provisioning profile, Info.plist).

## Clean Rebuild

```bash
swift package clean
rm -rf .build
swift build
```

## How It Works

`NetworkSpeedMonitor` polls all active, non-loopback network interfaces via `getifaddrs` on a configurable timer. On each tick it:

1. Reads raw byte counters (`ifi_ibytes` / `ifi_obytes`) from `if_data`.
2. Computes instantaneous throughput from the delta since the last snapshot.
3. Accumulates session totals and elapsed runtime.
4. Transitions to `.degraded` on repeated failures; drops the stale baseline after 3 consecutive errors to recover cleanly.

All published properties are annotated `@MainActor` and safe to observe directly from SwiftUI views.
