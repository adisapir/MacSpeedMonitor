# Network Scanner v1 Specification

## Instructions for the Coding Agent

Before making code changes:

1. Read this entire specification.
2. Inspect the existing `NetworkInfoView`, `NetworkSpeedMonitor`, network-interface discovery, OUI vendor lookup, sandbox entitlements, and tests.
3. Produce an implementation plan that maps every acceptance criterion to code and verification.
4. Keep the implementation scoped to local IPv4 device discovery in the existing Network Information tab.

During implementation:

1. Follow the existing Swift 6, SwiftUI, and `@MainActor` isolation patterns.
2. Keep network discovery off the main actor and publish observable state on the main actor.
3. Reuse the existing interface, default-router, and OUI vendor data sources where practical.
4. Add deterministic tests through injected discovery dependencies; tests must not depend on the developer's live LAN.
5. Do not add port scanning, packet inspection, analytics, or persistent device tracking.

Before marking the feature complete:

1. Satisfy every acceptance criterion and test scenario in this document.
2. Run the package tests, whitespace validation, and the Xcode Debug build.
3. Manually verify the scanner on at least one Wi-Fi or Ethernet LAN.
4. Update the README to describe the feature, its limits, and its privacy behavior.

---

## 1. Overview

### Feature name

Network Scanner v1

### Goal

Add a manually initiated local-network device scanner to the existing **Network Information** tab. The scanner helps a user see which devices respond on the Mac's currently active private IPv4 subnet without inspecting traffic or probing device services.

### Primary workflow

1. The user opens **Network Information**.
2. Existing network-interface cards remain at the top of the tab.
3. A **Devices on Your Network** section appears below the interface cards.
4. The section is initially idle and does not generate network traffic.
5. The user presses **Scan Network**.
6. The app displays progress and adds devices incrementally as they are found.
7. The user may cancel an active scan.
8. On completion, the app shows the discovered-device count and completion time.
9. The user may press **Scan Again** to refresh the results.

### Product principles

- Scanning is explicit and manual. Opening the tab never starts a scan.
- Scanning is confined to the directly connected private IPv4 subnet.
- Results are informative rather than authoritative. Network policy and device firewalls may hide devices.
- No device inventory is persisted between app launches.
- The existing **Wi-Fi Scan** tab remains separate and unchanged.

## 2. Scope

### Included in v1

- Select the active private IPv4 interface associated with the default route.
- Derive its directly connected subnet from its IPv4 address and netmask.
- Discover responsive IPv4 hosts with sandbox-compatible reachability traffic.
- Show partial results while scanning.
- Resolve hostnames and MAC addresses when macOS makes them available.
- Derive vendor names from available MAC addresses using the bundled Wireshark OUI data.
- Identify the local Mac and default router.
- Support progress, cancellation, rescan, partial success, and actionable error states.
- Support subnets containing no more than 256 total addresses.

### Excluded from v1

- IPv6 discovery.
- Public, remote, routed, VPN, tunnel, loopback, or link-local network scanning.
- TCP or UDP port scanning and service enumeration.
- Packet capture, payload inspection, traffic analysis, or credential collection.
- User-defined address ranges or arbitrary subnet entry.
- Device history, change tracking, alerts, notifications, favorites, or custom names.
- Export, sharing, cloud synchronization, or analytics.
- Wake-on-LAN or actions that modify discovered devices.

## 3. Functional Requirements

### 3.1 Active network selection

- Select the up, running, non-loopback interface used by the system's default IPv4 route.
- The selected interface must have an RFC 1918 address in `10.0.0.0/8`, `172.16.0.0/12`, or `192.168.0.0/16`.
- Exclude virtual and tunnel interfaces using the project's existing interface filtering conventions, including `utun`, `tun`, `tap`, `ppp`, `ipsec`, WireGuard, Tailscale, ZeroTier, and VPN-style prefixes.
- Derive the network address, broadcast address, prefix length, and candidate host range from the interface address and netmask.
- Exclude the network and broadcast addresses from scan targets. Include the local Mac and router in displayed results using known system metadata even when the local address is not probed.
- Reject malformed or non-contiguous netmasks.
- Reject subnets containing more than 256 total addresses rather than silently scanning only part of the subnet.
- Treat `/31` and `/32` networks as unsupported for v1 because they do not provide a conventional host range.

### 3.2 Scan lifecycle

- Only one scan may run at a time.
- Pressing **Scan Network** starts a scan only from the idle, completed, cancelled, or failed state.
- During a scan, replace the primary action with **Cancel Scan**. Repeated scan requests must not create overlapping tasks.
- Process hosts with a bounded concurrency limit of 32.
- Use a per-host reachability timeout of 1 second and no more than one retry.
- Check cancellation before scheduling a host, after each network wait, and before publishing an event.
- Cancelling stops new probes promptly, preserves devices found during that scan, and transitions to the cancelled state.
- A scan must not outlive the coordinator that owns it. Leaving Network Information may cancel active work, but completed results remain available while the app process remains alive.
- A new scan keeps the previous successful results visible and marks them stale. Rediscovered devices become current as events arrive. At completion, remove devices that remained stale.
- A failed scan keeps the last successful result set visible and marked stale.

### 3.3 Discovery and enrichment

- Use a sandbox-compatible ICMP echo or equivalent non-port-based reachability mechanism. Do not probe TCP or UDP service ports as a discovery fallback.
- Discovery traffic must be limited to candidate addresses in the derived local subnet.
- Publish a device as soon as it is known from local/router metadata or responds to discovery traffic.
- Measure response time using a monotonic clock and present it in milliseconds. Leave it unavailable when the device was identified through system metadata but did not produce a measurable response.
- Attempt reverse-DNS hostname resolution without delaying the core scan completion indefinitely.
- Read MAC addresses only from system-supported neighbor information populated through normal local-network interaction. Do not require elevated privileges.
- Normalize MAC addresses to uppercase colon-separated form before lookup and display.
- Reuse `OUIVendorLookup` for vendor resolution. Represent unknown, randomized, or unavailable vendor information as absent or a clear user-facing fallback rather than a fabricated manufacturer.
- Treat hostname, MAC address, vendor, and response time as optional enrichment. Their absence is not a scan failure.
- Merge enrichment updates into the existing device record for the same IPv4 address.

### 3.4 Identity, ordering, and deduplication

- A device's stable identity for one app session is its normalized IPv4 address.
- Never display more than one row for the same IPv4 address.
- Prefer a resolved hostname as the title. Otherwise use **Router**, **This Mac**, or **Unknown Device**, in that order of applicability.
- Sort devices in this order:
  1. Default router.
  2. This Mac.
  3. Remaining devices by numeric IPv4 address, ascending.
- Do not sort IPv4 addresses lexicographically.
- Updating hostname, MAC, vendor, latency, or last-seen metadata must not create a new device or change its identity.

## 4. User Experience

### 4.1 Placement and visual structure

- Embed the scanner below the existing network-interface cards inside the current `NetworkInfoView` scroll view.
- Add a section header with:
  - Title: **Devices on Your Network**
  - Subtitle: **Discover devices responding on your current local network**
  - An `InfoButton` using the established help presentation.
  - The state-appropriate **Scan Network**, **Scan Again**, or **Cancel Scan** button.
- Match existing `GlassCard`, typography, spacing, colors, hover behavior, and light/dark appearance.
- Do not add another sidebar tab or move the existing Wi-Fi Scan tab.

### 4.2 Device presentation

Each row or card must show:

- Friendly hostname or fallback device title.
- IPv4 address in monospaced text.
- MAC address when available.
- Vendor when available.
- Response time when available.
- A **Router** badge for the default router.
- A **This Mac** badge for the local device.
- A stale visual treatment during rescan or after failure without making text inaccessible.

Long hostnames and vendor names must truncate gracefully and expose their complete value through standard macOS hover help or accessibility text. A context menu may copy the IPv4 address, MAC address, or all available device details, following existing copy behavior.

### 4.3 Progress and summary

- While scanning, show a determinate progress indicator based on completed targets divided by total targets.
- Show concise text such as **Scanning 42 of 254 addresses - 7 devices found**.
- Update progress incrementally without excessive animation or layout movement.
- On successful completion, show **N devices found** and **Updated [time]**.
- Use correct singular/plural wording.
- Progress must reach 100% for a completed scan even when no devices respond.

### 4.4 Information and privacy help

The scanner `InfoButton` must explain in plain language:

- The scan checks only the Mac's current local IPv4 network.
- It sends reachability requests but does not inspect browsing activity or payload data.
- Firewalls, sleep state, client isolation, and network policy can hide devices.
- Hostname, MAC, vendor, and response time may be unavailable.
- The app does not save or upload the device list.

### 4.5 Accessibility

- All actions must be keyboard reachable and use standard button semantics.
- Progress must expose an accessibility label and current value.
- Each device must have a concise combined VoiceOver description containing its name, IP address, badges, and available metadata.
- Do not communicate stale/current state or device type by color alone.
- Preserve readable contrast in light and dark appearances and with Increase Contrast enabled.
- Respect Reduce Motion for result insertion and progress animations.

## 5. State and Error Behavior

The UI and coordinator must represent these states explicitly:

| State | Required behavior |
| --- | --- |
| Idle | Explain the feature and show **Scan Network**. No scan traffic is generated. |
| Scanning | Show determinate progress, partial results, and **Cancel Scan**. Previous results are marked stale until rediscovered. |
| Completed | Show current results, count, completion time, and **Scan Again**. |
| Completed empty | Explain that no other responding devices were found; still show This Mac when local metadata is valid. |
| Partial success | Show discovered devices plus a non-blocking warning when some probes or enrichment operations failed. |
| Cancelled | Preserve results found so far, label the scan cancelled, and show **Scan Again**. |
| No active interface | Explain that an active private IPv4 Wi-Fi or Ethernet connection is required. |
| Invalid subnet | Explain that the current subnet information could not be interpreted safely. |
| Oversized subnet | Explain that v1 supports networks containing at most 256 addresses and do not start probing. |
| Failure | Keep prior results if available, show a concise error and recovery action, and allow retry. |

Network changes during a scan must cancel the current scan and move to an actionable failure state indicating that the active network changed. Normal host timeouts are expected misses, not user-facing errors. Enrichment failures should produce partial success only when they are widespread enough to affect the usefulness of the results.

## 6. Technical Contract

Names may be adapted to existing project conventions, but the following responsibilities and data must remain distinct.

### 6.1 Discovered device model

Define a `Sendable`, `Identifiable`, and `Hashable` value type equivalent to:

```swift
public struct DiscoveredNetworkDevice: Sendable, Identifiable, Hashable {
    public var id: String { ipv4Address }
    public let ipv4Address: String
    public var hostname: String?
    public var macAddress: String?
    public var vendorName: String?
    public var responseTimeMilliseconds: Double?
    public var isRouter: Bool
    public var isLocalDevice: Bool
    public var lastSeenAt: Date
    public var isStale: Bool
}
```

The initializer must normalize and validate input before a value reaches observable UI state. Invalid IP or MAC values must be discarded rather than displayed.

### 6.2 Scan request and interface descriptor

The scanner must receive an immutable, sendable descriptor containing:

- Interface name.
- Local IPv4 address.
- Netmask or validated prefix length.
- Default-router IPv4 address when available.
- Network and broadcast addresses.
- Ordered candidate host addresses.

Subnet derivation must be a pure, independently tested operation.

### 6.3 Scanner service

Define an injectable scanner abstraction equivalent to:

```swift
protocol NetworkScanning: Sendable {
    func scan(
        request: NetworkScanRequest
    ) -> AsyncThrowingStream<NetworkScanEvent, Error>
}
```

The event stream must support:

- Scan started with total target count.
- Progress with completed target count and discovered-device count.
- Device discovered or enriched.
- Non-fatal warning.
- Scan completed with timestamp.
- Cancellation through Swift task cancellation.

The stream must finish exactly once. It must not emit values after cancellation or completion.

### 6.4 Observable coordination

- Prefer a focused `@MainActor` observable coordinator owned by `NetworkInfoView`; integration in `NetworkSpeedMonitor` is acceptable only if scanner state remains isolated from throughput and Wi-Fi scan state.
- Observable state must include scan phase, ordered devices, completed and total target counts, last completion time, and optional warning/error text.
- Store devices internally by normalized IPv4 address for deterministic merging, then expose the required sorted array.
- Keep the active scan task so it can be cancelled explicitly and during teardown.
- Ignore late events from superseded scans by associating events with a scan identifier.
- Dependency-inject the scanner, interface resolver, clock, hostname resolver, neighbor/MAC resolver, and vendor lookup where required for deterministic tests.

### 6.5 Concurrency and performance

- Use structured concurrency and a bounded task group or equivalent mechanism.
- Do not create one unbounded task per address.
- Never perform blocking DNS, neighbor-table, or reachability work on the main actor.
- Throttle UI progress publication if necessary to avoid more than 10 visual updates per second while still publishing each discovered device promptly.
- A conventional `/24` scan must remain cancellable and keep scrolling, navigation, throughput monitoring, and Wi-Fi scan UI responsive.
- Release sockets, continuations, timers, and tasks on every completion and cancellation path.

### 6.6 Security and permissions

- Use only APIs compatible with the existing macOS App Sandbox and network client entitlement.
- Do not execute shell tools such as `ping`, `arp`, or `nmap` from the app.
- Do not request administrator privileges, packet-capture permissions, or additional personal-information access.
- Add a local-network usage description only if required by the chosen public macOS API and deployment target.
- Log aggregate lifecycle and errors through `OSLog`; never log a complete device inventory at the default level.

## 7. Acceptance Criteria

### Functional acceptance

- [ ] Network Scanner is embedded below interface cards in Network Information.
- [ ] Opening Network Information does not start a scan.
- [ ] **Scan Network** discovers devices only on the selected directly connected private IPv4 subnet.
- [ ] Partial results and accurate progress appear while scanning.
- [ ] The user can cancel and start a later scan without overlapping work.
- [ ] Router and This Mac are identified when system metadata is available.
- [ ] Devices are deduplicated by IP and enriched in place.
- [ ] Results sort router first, This Mac second, then numeric IPv4 order.
- [ ] Previous results remain visible and stale during rescan, then reconcile at completion.
- [ ] All specified empty, partial, cancellation, interface, subnet, network-change, and failure states are actionable.
- [ ] No TCP or UDP service-port scan is performed.

### Privacy and security acceptance

- [ ] Discovery traffic never leaves the derived local subnet.
- [ ] The app does not capture or inspect payload data.
- [ ] Device results are not persisted or uploaded.
- [ ] The scanner requires no elevated privileges or external command execution.
- [ ] Help text accurately explains traffic, limitations, optional metadata, and retention.

### Performance acceptance

- [ ] Scan concurrency never exceeds 32 host probes.
- [ ] The Network Information UI remains responsive during a `/24` scan.
- [ ] Throughput monitoring and Wi-Fi scanning continue without material interruption.
- [ ] Cancellation prevents new probes promptly and releases active work.
- [ ] Completed and cancelled scans leave no running scanner task or timer.

### Accessibility and UX acceptance

- [ ] UI matches the existing SwiftUI visual language in light and dark modes.
- [ ] Scan, cancel, retry, copy, and help actions are keyboard accessible.
- [ ] VoiceOver announces progress, device identity, badges, and available metadata clearly.
- [ ] State and stale status are not communicated by color alone.
- [ ] Long values truncate without breaking layout and remain available accessibly.

### Technical acceptance

- [ ] Subnet, sorting, deduplication, enrichment, progress, cancellation, timeout, and stale-result logic have deterministic unit tests.
- [ ] Live-network behavior is abstracted so the test suite does not scan the developer's LAN.
- [ ] Swift package tests pass.
- [ ] The Xcode Debug build succeeds with code signing disabled.
- [ ] `git diff --check` reports no whitespace errors.
- [ ] Existing Home, Network Information, Wi-Fi Scan, About, Settings, monitoring, and widget behavior regressions are not introduced.

## 8. Test Plan

### Unit tests

- Derive correct candidate ranges for `/24`, `/25`, `/30`, and other valid subnets up to 256 total addresses.
- Reject non-contiguous netmasks, `/31`, `/32`, public, loopback, link-local, tunnel, and oversized subnets.
- Exclude network and broadcast addresses and identify local/router addresses.
- Compare and sort IPv4 addresses numerically.
- Deduplicate repeated discoveries and merge later hostname, MAC, vendor, and latency values.
- Normalize valid MAC addresses and reject malformed values.
- Map available MAC prefixes through the existing OUI vendor database and handle unknown/private values.
- Calculate monotonic progress correctly, including empty completion and cancellation.
- Enforce the concurrency ceiling and per-host timeout using controllable test probes.
- Stop producing events after cancellation or completion.
- Mark old results stale, refresh rediscovered records, remove remaining stale records on success, and retain them on failure.
- Ignore events belonging to an older superseded scan identifier.

### Integration and UI scenarios

- Scan a normal Wi-Fi `/24` and an Ethernet LAN.
- Verify no traffic occurs before the user starts a scan.
- Verify partial devices appear before completion and remain in stable order.
- Repeatedly press the scan action and confirm only one scan runs.
- Cancel early, midway, and near completion; confirm prompt cleanup and recoverable UI.
- Switch tabs during a scan and verify the documented cancellation behavior.
- Disconnect or change networks during a scan and verify the network-changed state.
- Test no responding peers, hostname failures, unavailable MAC/vendor data, and widespread enrichment failure.
- Verify router and This Mac badges and unavailable response-time behavior.
- Verify many rows, long names, context-menu copying, light/dark appearance, Increase Contrast, Reduce Motion, keyboard navigation, and VoiceOver.
- Run throughput monitoring during a scan and confirm its updates remain responsive.
- Run the separate Wi-Fi Scan feature and confirm its behavior is unchanged.

### Required verification commands

```bash
swift test
git diff --check
xcodebuild \
  -project WiFiPulse.xcodeproj \
  -scheme MacSpeedMonitor \
  -configuration Debug \
  -derivedDataPath /tmp/SimpleSpeedMonitor-DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## 9. Documentation Requirements

Update the README with:

- A concise Network Scanner feature description.
- Its placement under Network Information.
- Manual-scan behavior.
- IPv4, private-subnet, and 256-address limits.
- The fact that firewalls and network isolation may hide devices.
- The privacy statement that results are local, not inspected, persisted, or uploaded.
- Any macOS permission or sandbox requirement introduced by the final implementation.

## 10. Definition of Done

- [ ] The implementation matches this specification without expanding into port or remote-network scanning.
- [ ] All functional, privacy, security, performance, accessibility, and technical acceptance criteria pass.
- [ ] Automated tests cover pure logic, state coordination, cancellation, and failure behavior.
- [ ] Manual testing confirms useful discovery on a real local network.
- [ ] Required verification commands succeed.
- [ ] README and relevant inline documentation are current.
- [ ] No known regression or leaked scan task remains.
