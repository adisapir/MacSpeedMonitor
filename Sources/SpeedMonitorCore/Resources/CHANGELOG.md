# Change Log

## 2026-06-29

- Added an enhanced device scan that gathers ping TTL and HTTP server header details, with the option to scan unknown devices only or all devices.
- Included enhanced scan results in AI recognition requests to improve device identification.
- Improved device display names using the recognized device type, and surfaced the AI-detected type as a badge.
- Kept AI-recognized names for devices across later scans (matched by MAC address or hostname) and stopped re-treating already-recognized devices as unknown.
- Created the device history file automatically on first launch when it does not exist.
- Refined AI scan request logging format.

## 2026-06-24

- Embedded the change log in the app and displayed it in the About view with refined formatting.
- Added menu-bar display of current upload and download speeds.

## 2026-06-23

- Added local network port scanning and included completed port results in AI recognition requests.
- Improved AI-recognized device icons and persisted recognized icons by MAC address.
- Fixed throughput chart history expanding beyond the configured duration after long sampling gaps.
- Added a consistent bundled application icon to standalone and DMG distribution builds.

## 2026-06-21

- Added persistent local device and AI insight history matched by MAC address.
- Replaced Unknown Device labels with recognized AI-suggested names.
- Improved device discovery with hostname and DHCP hostname detection.
- Added optional OpenAI-powered recognition for unknown network devices.
- Enhanced local device discovery with MAC address and vendor identification.
- Added a local network scanner to the renamed Connected Network tab.

## 2026-06-20

- Added a configurable WiFiPulse widget for monitoring network speed.

## 2026-06-19

- Added contextual information and help controls for network details.

## 2026-06-18

- Updated the minimum supported macOS version to 15.6.

## 2026-06-17

- Added Wireshark OUI-based vendor lookup with generated data and tests.
- Expanded Wi-Fi network details with additional connection attributes.

## 2026-06-16

- Improved Wi-Fi scanning and location-permission handling.
- Added and documented the Xcode project configuration and app assets.

## 2026-06-15

- Fixed Wi-Fi radar animation and refresh synchronization.
- Added maximum upload and download throughput statistics for the current session.

## 2026-06-14

- Improved Wi-Fi radar refresh behavior and scan-state management.
- Added location-permission guidance and network visibility warnings.
- Removed iOS support to focus the application on macOS.
- Added the Wi-Fi radar visualization.
- Added a resizable and collapsible navigation sidebar.
- Hid virtual network adapters from the common interface list.
- Improved throughput charts with a legend plus refined styling and clearer axes.
- Added network link-speed detection and manual interface refresh controls.
- Added macOS menu-bar navigation commands.
