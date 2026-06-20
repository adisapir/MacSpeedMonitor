# SimpleSpeedMonitor

A lightweight SwiftUI network speed monitor for macOS.

## Package Structure

| Target | Type | Description |
|---|---|---|
| `SpeedMonitorCore` | Library | Reusable monitor + SwiftUI UI |
| `MacSpeedMonitorApp` | Executable | macOS app entry point (`swift run`) |
| `WiFiPulse.xcodeproj` / `MacSpeedMonitor` | Xcode app target | macOS app target for Xcode run, signing, capabilities, and packaging |

**Platform requirements:** macOS 13+

The app source of truth remains under `Sources/`. The Xcode project reuses the existing `MacSpeedMonitorApp` entry point and `SpeedMonitorCore` UI/monitor code. The `WiFiPulse/ContentView.swift` and `WiFiPulse/WiFiPulseApp.swift` files are only Xcode template files and are intentionally ignored; `WiFiPulse/Assets.xcassets` is kept for Xcode-managed app assets.

## Features

- **Live throughput** — download and upload speed, updated every second
- **Throughput History Chart** — dual-graphed (download in blue, upload in green) area chart with configurable duration (30–300 s, default 60 s) and dynamic Y-axis unit scaling
- **Left Navigation Sidebar** — vertical tabbed navigation with resizable width, hover effects, and collapsible layout (compact icon-only vs full list titles)
- **macOS Menu Bar Commands** — Settings (Cmd+,) and About commands switch window views directly
- **Modern User Interface** — glassmorphic "Liquid Glass" cards with glowing gradients, hover scaling, and dark/light/system theme support
- **Network Interfaces** — active non-loopback adapters only, showing IP address, Wi-Fi link rate (via `CoreWLAN`), wired link speed (via `IOKit`), and friendly Wi-Fi generation label (Wi-Fi 5 through Wi-Fi 7); auto-refreshed via `NWPathMonitor` + manual Refresh button
- **Local Network Scanner** — manually discover responding devices on the current private IPv4 subnet from the Connected Network tab, with incremental progress, cancellation, hostname and response-time details, and Router / This Mac identification
- **Optional AI Device Recognition** — use your own OpenAI API key to request cautious, inline recognition suggestions for unknown scanner entries, individually or in redacted batches
- **Wi-Fi Scan Radar** — nearby Wi-Fi networks shown as a radar map with signal-sized dots, 2.4/5/6 GHz band colors, connected-network highlighting, hover detail popovers, manual refresh, and 30 s auto-refresh; extended details include SSID, BSSID, vendor/OUI, signal percentage, router Wi-Fi generation, channel width, same/overlapping-channel AP counts, country code, and security, with right-click copy for a scanned router's full details
- **Dynamic Dock App Icon** — dynamically rendered vector speed logo on startup
- **Appearance & Unit Settings** — configure theme (Light / Dark / Match System), speed units (MB/s vs Mbps), and throughput history duration
- **Session totals** — cumulative bytes downloaded and uploaded since monitoring started
- **Runtime counter** — elapsed time displayed as `MM:SS` or `HH:MM:SS`
- **Status reporting** — `idle`, `running`, `degraded`, or `stopped` states via `MonitorStatus`
- **Error recovery** — detects `getifaddrs` failures and interface counter resets; auto-recovers after transient errors
- **Configurable sampling interval** — defaults to 1 s, minimum 0.2 s

## Run (macOS)

### SwiftPM

```bash
cd /path/to/SimpleSpeedMonitor
swift run
```

### Xcode Project Mode

Open the Xcode project:

```bash
open WiFiPulse.xcodeproj
```

In Xcode:

1. Select the `MacSpeedMonitor` scheme.
2. Select `My Mac` as the run destination.
3. Confirm the signing team under the `MacSpeedMonitor` target if Xcode asks.
4. Run with `Product > Run` or `Cmd+R`.

The Xcode app target uses `Sources/MacSpeedMonitorApp/Info.plist` and `Sources/MacSpeedMonitorApp/MacSpeedMonitor.entitlements`, so Location Services, sandboxing, network access, signing, archiving, and future packaging are managed through the Xcode project.

## Build (macOS)

### SwiftPM

```bash
swift build
```

### Xcode

```bash
xcodebuild -project WiFiPulse.xcodeproj -scheme MacSpeedMonitor -configuration Debug build
```

For local compile validation without requiring a signing certificate:

```bash
xcodebuild -project WiFiPulse.xcodeproj -scheme MacSpeedMonitor -configuration Debug -derivedDataPath /tmp/SimpleSpeedMonitorDerivedData CODE_SIGNING_ALLOWED=NO build
```

## Wi-Fi Scan Permissions

macOS requires Location Services permission before third-party apps can read Wi-Fi SSID/BSSID details through `CoreWLAN`. Open the Wi-Fi Scan pane to trigger the permission request. If denied, enable Location Services for MacSpeedMonitor in System Settings.

The SwiftPM executable embeds `Sources/MacSpeedMonitorApp/Info.plist` at link time so the location usage description is available when running with `swift run`. The Xcode app target uses the same plist and the dedicated entitlements file for the signed app bundle.

## Local Network Scanner

Open **Connected Network** and choose **Scan Network** to check the Mac's directly connected private IPv4 network. Scans are always manual, are limited to networks containing no more than 256 addresses, and do not probe service ports or inspect network payloads.

Results remain local to the current app session and are not saved or uploaded. Host firewalls, sleeping devices, guest-network isolation, and router policy can prevent devices from responding, so the result list may not contain every connected device. Hostnames, hardware addresses, vendors, and response times are shown only when macOS and the responding device make them available.

### AI Device Recognition (Optional)

The Connected Network scanner can ask OpenAI for a cautious category suggestion for entries shown as **Unknown Device**. Configure your own OpenAI API key under **Settings > AI Device Recognition**, then use **AI Scan** for all unknown devices or right-click one device and choose **Recognize Device through AI**.

- The key is stored in macOS Keychain and is never included in source code, preferences, or logs.
- Requests use `gpt-5.4-mini` through OpenAI's Responses API and are billed to the user's OpenAI account.
- Only a temporary item ID, vendor name, Router / This Mac flags, and response time are sent. Private IP addresses and MAC addresses are never sent.
- Requests contain at most 25 devices per batch, do not use web search or tools, and are not automatically retried.
- Results are labeled as unverified AI suggestions, stay only in memory for the current app session, and never replace scanner facts.
- Vendor and timing metadata may be insufficient to recognize a device. A low-confidence or unavailable result is expected rather than a definitive identity.

API keys stored in a local desktop application do not have server-grade isolation. Use a dedicated OpenAI project key with appropriate usage limits, and remove it from Settings when it is no longer needed.

## Wi-Fi Vendor/OUI Data

Wi-Fi Scan resolves AP vendors by comparing each BSSID against the bundled `Sources/SpeedMonitorCore/Resources/oui-vendors.tsv` resource. That file is generated from Wireshark's public manufacturer database and preserves 24-bit, 28-bit, and 36-bit MAC blocks, then stores vendor names once and maps each prefix to a vendor index to keep the resource smaller than the raw source file.

To refresh the bundled data:

```bash
Scripts/generate-oui-vendors.py
```

The runtime lookup checks the longest available prefix first and also tries the universal-address variant for locally administered AP BSSIDs.

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
