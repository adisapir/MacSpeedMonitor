# SimpleSpeedMonitor

SimpleSpeedMonitor is a native macOS app for viewing current network activity, nearby Wi-Fi networks, and devices on your local network.

## Features

- Live download and upload speeds
- Throughput history, session totals, and runtime
- Active network-interface details
- Nearby Wi-Fi scanning with signal, channel, band, security, and vendor information
- Manual local-network device discovery
- Optional AI-assisted recognition for unknown devices
- Light, dark, and system appearance modes
- Configurable speed units and chart duration

## Requirements

- macOS 15.6 or later
- Xcode with macOS development support

Apple On-Device device recognition additionally requires macOS 26, a compatible Apple Intelligence Mac, and Apple Intelligence enabled.

## Getting Started

Clone the repository and open the Xcode project:

```bash
git clone https://github.com/adisapir/MacSpeedMonitor.git
cd MacSpeedMonitor
open WiFiPulse.xcodeproj
```

In Xcode:

1. Select the `MacSpeedMonitor` scheme.
2. Select **My Mac** as the destination.
3. Choose your development team under **Signing & Capabilities** if Xcode requests one.
4. Press **Cmd+R** to build and run.

You can also run the Swift package directly:

```bash
swift run
```

Run the test suite with:

```bash
swift test
```

## Permissions

Some features require macOS permission:

- **Location Services** allows macOS to reveal nearby Wi-Fi network names and identifiers. The app requests it when you open Wi-Fi Scan.
- **Local Network** access may be requested when you manually scan for devices on your network.

If a permission was previously denied, enable it for MacSpeedMonitor under **System Settings > Privacy & Security**.

## Optional AI Device Recognition

Under **Settings > AI Device Recognition**, choose one of these methods:

- **Apple On-Device** — runs locally and requires no API key.
- **OpenAI API** — requires an [OpenAI API key](https://platform.openai.com/api-keys).
- **Google Gemini** — requires a [Gemini API key](https://aistudio.google.com/app/apikey).

AI recognition is optional. Suggestions are clearly labeled and may not identify every device accurately.
