import Foundation
import Combine
import Darwin
import OSLog
import Network
import CoreWLAN
import IOKit
import IOKit.network
import SystemConfiguration

@MainActor
public final class NetworkSpeedMonitor: ObservableObject {
    private enum WidgetSnapshot {
        static let appGroup = "group.com.adisapir.MacSpeedMonitor"
        static let downloadKey = "widget.downloadBytesPerSecond"
        static let uploadKey = "widget.uploadBytesPerSecond"
        static let updatedAtKey = "widget.updatedAt"
        static let isRunningKey = "widget.isRunning"

        static func publish(download: Double, upload: Double, updatedAt: Date, isRunning: Bool) {
            guard let defaults = UserDefaults(suiteName: appGroup) else { return }
            defaults.set(download, forKey: downloadKey)
            defaults.set(upload, forKey: uploadKey)
            defaults.set(updatedAt.timeIntervalSince1970, forKey: updatedAtKey)
            defaults.set(isRunning, forKey: isRunningKey)
        }
    }

    @Published public private(set) var downloadBytesPerSecond: Double = 0
    @Published public private(set) var uploadBytesPerSecond: Double = 0
    @Published public private(set) var maxDownloadBytesPerSecond: Double = 0
    @Published public private(set) var maxUploadBytesPerSecond: Double = 0
    @Published public private(set) var totalDownloadBytes: UInt64 = 0
    @Published public private(set) var totalUploadBytes: UInt64 = 0
    @Published public private(set) var runtime: TimeInterval = 0
    @Published public private(set) var status: MonitorStatus = .idle
    @Published public private(set) var lastErrorDescription: String?
    @Published public private(set) var lastUpdatedAt: Date?
    @Published public private(set) var speedHistory: [SpeedHistoryPoint] = []
    @Published public private(set) var activeInterfaces: [NetworkInterfaceInfo] = []
    @Published public private(set) var wifiScanResults: [WiFiNetworkInfo] = []
    @Published public private(set) var lastWiFiScanAt: Date?
    @Published public private(set) var isWiFiScanRefreshing = false
    @Published public private(set) var wifiScanErrorDescription: String?
    @Published public private(set) var wifiScanRefreshToken = 0
    @Published public private(set) var networkScanPhase: NetworkScanPhase = .idle
    @Published public private(set) var networkScanDevices: [DiscoveredNetworkDevice] = []
    @Published public private(set) var networkScanCompletedTargets = 0
    @Published public private(set) var networkScanTotalTargets = 0
    @Published public private(set) var lastNetworkScanAt: Date?
    @Published public private(set) var networkScanWarning: String?
    @Published public private(set) var aiRecognitionStates: [String: DeviceAIRecognitionState] = [:]
    @Published public private(set) var isAIRecognitionRunning = false
    @Published public private(set) var aiRecognitionCompletedCount = 0
    @Published public private(set) var aiRecognitionTotalCount = 0
    @Published public private(set) var aiRecognitionErrorDescription: String?
    @Published public private(set) var hasOpenAIAPIKey = false
    @Published public private(set) var deviceHistoryRecordCount = 0
    @Published public private(set) var deviceHistoryErrorDescription: String?

    private var timerCancellable: AnyCancellable?
    private var wifiScanTimerCancellable: AnyCancellable?
    private var networkScanTask: Task<Void, Never>?
    private var activeNetworkScanRequest: NetworkScanRequest?
    private var networkScanID: UUID?
    private var networkScanGeneration = UUID()
    private var aiRecognitionTask: Task<Void, Never>?
    private var aiRecognitionID: UUID?
    private let aiRecognitionProvider: any AIRecognitionProviding
    private let deviceHistoryStore: any DeviceHistoryStoring
    private var persistedDeviceRecords: [String: PersistedDeviceRecord]
    private var previousSnapshot: InterfaceSnapshot?
    private let samplingInterval: TimeInterval
    private var consecutiveFailureCount = 0
    private var startDate = Date()
    private var pathMonitor: NWPathMonitor?

    nonisolated private static let logger = Logger(subsystem: "MacSpeedMonitor", category: "NetworkSpeedMonitor")

    public convenience init(samplingInterval: TimeInterval = 1.0) {
        self.init(
            samplingInterval: samplingInterval,
            aiRecognitionProvider: OpenAIRecognitionProvider(),
            deviceHistoryStore: LocalDeviceHistoryStore.shared
        )
    }

    init(
        samplingInterval: TimeInterval,
        aiRecognitionProvider: any AIRecognitionProviding,
        deviceHistoryStore: any DeviceHistoryStoring = LocalDeviceHistoryStore.shared
    ) {
        self.samplingInterval = max(0.2, samplingInterval)
        self.aiRecognitionProvider = aiRecognitionProvider
        self.deviceHistoryStore = deviceHistoryStore
        self.hasOpenAIAPIKey = aiRecognitionProvider.hasAPIKey
        do {
            let records = try deviceHistoryStore.load()
            self.persistedDeviceRecords = records
            self.deviceHistoryRecordCount = records.count
        } catch {
            self.persistedDeviceRecords = [:]
            self.deviceHistoryErrorDescription = error.localizedDescription
        }
        if case .success(let snapshot) = Self.captureSnapshot() {
            previousSnapshot = snapshot
        }
        
        refreshInterfaces()
        setupPathMonitor()
    }
    
    private func setupPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in
                self?.refreshInterfaces()
            }
        }
        let queue = DispatchQueue(label: "NetworkPathMonitorQueue")
        monitor.start(queue: queue)
        self.pathMonitor = monitor
    }
    
    public func refreshInterfaces() {
        self.activeInterfaces = getNetworkInterfaces()
        guard networkScanPhase == .scanning,
              let request = activeNetworkScanRequest
        else { return }

        let stillConnected = activeInterfaces.contains {
            $0.name == request.interfaceName && $0.family == "IPv4" && $0.address == request.localIPv4Address
        }
        if !stillConnected {
            stopNetworkScan(for: .networkChanged)
        }
    }

    public func startNetworkScan() {
        guard networkScanPhase != .scanning else { return }

        cancelAIRecognition()
        networkScanGeneration = UUID()

        let request: NetworkScanRequest
        do {
            request = try ActiveNetworkScanResolver.resolve()
        } catch let error as NetworkScanError {
            networkScanPhase = .failed(error.localizedDescription)
            networkScanWarning = nil
            return
        } catch {
            networkScanPhase = .failed(error.localizedDescription)
            networkScanWarning = nil
            return
        }

        let scanID = UUID()
        networkScanID = scanID
        activeNetworkScanRequest = request
        networkScanCompletedTargets = 0
        networkScanTotalTargets = request.candidateHostAddresses.filter {
            $0 != request.localIPv4Address
        }.count
        networkScanWarning = nil
        var deviceStore = NetworkScanDeviceStore(devices: networkScanDevices)
        deviceStore.markAllStale()
        networkScanDevices = deviceStore.sortedDevices
        networkScanPhase = .scanning

        let stream = LocalNetworkScanner().scan(request: request)
        networkScanTask = Task { [weak self] in
            do {
                for try await event in stream {
                    guard let self, self.networkScanID == scanID else { return }
                    self.handleNetworkScanEvent(event)
                }
            } catch is CancellationError {
                guard let self, self.networkScanID == scanID else { return }
                if self.networkScanPhase == .scanning {
                    self.networkScanPhase = .cancelled
                }
                self.finishNetworkScanTask(scanID: scanID)
            } catch {
                guard let self, self.networkScanID == scanID else { return }
                self.networkScanPhase = .failed(error.localizedDescription)
                self.finishNetworkScanTask(scanID: scanID)
            }
        }
    }

    public func cancelNetworkScan() {
        guard networkScanPhase == .scanning else { return }
        networkScanPhase = .cancelled
        networkScanTask?.cancel()
    }

    private func stopNetworkScan(for error: NetworkScanError) {
        networkScanPhase = .failed(error.localizedDescription)
        networkScanTask?.cancel()
    }

    private func handleNetworkScanEvent(_ event: NetworkScanEvent) {
        switch event {
        case .started(let totalTargets):
            networkScanTotalTargets = totalTargets

        case .device(let device):
            mergeNetworkScanDevice(device)

        case .progress(let completedTargets, _):
            networkScanCompletedTargets = completedTargets

        case .warning(let warning):
            networkScanWarning = warning

        case .completed(let completedAt):
            networkScanCompletedTargets = networkScanTotalTargets
            var deviceStore = NetworkScanDeviceStore(devices: networkScanDevices)
            deviceStore.removeStaleDevices()
            networkScanDevices = deviceStore.sortedDevices
            let activeIdentities = Set(networkScanDevices.map(\.aiIdentity))
            aiRecognitionStates = aiRecognitionStates.filter { activeIdentities.contains($0.key) }
            persistDeviceHistory()
            lastNetworkScanAt = completedAt
            networkScanPhase = .completed
            if let scanID = networkScanID {
                finishNetworkScanTask(scanID: scanID)
            }
        }
    }

    private func mergeNetworkScanDevice(_ update: DiscoveredNetworkDevice) {
        var update = update
        if let macAddress = update.macAddress,
           let persisted = persistedDeviceRecords[macAddress] {
            update = persisted.enriching(update)
            if let recognition = persisted.aiRecognition {
                aiRecognitionStates[update.aiIdentity] = .recognized(recognition)
            }
        }
        var deviceStore = NetworkScanDeviceStore(devices: networkScanDevices)
        deviceStore.merge(update)
        networkScanDevices = deviceStore.sortedDevices
    }

    private func finishNetworkScanTask(scanID: UUID) {
        guard networkScanID == scanID else { return }
        networkScanTask = nil
        activeNetworkScanRequest = nil
    }

    public var unknownDevicesForAIRecognition: [DiscoveredNetworkDevice] {
        networkScanDevices.filter(\.isUnknownForAIRecognition)
    }

    public func refreshOpenAIAPIKeyAvailability() {
        hasOpenAIAPIKey = aiRecognitionProvider.hasAPIKey
    }

    public func clearDeviceHistory() {
        do {
            try deviceHistoryStore.remove()
            persistedDeviceRecords = [:]
            deviceHistoryRecordCount = 0
            deviceHistoryErrorDescription = nil
            aiRecognitionStates = [:]
        } catch {
            deviceHistoryErrorDescription = error.localizedDescription
        }
    }

    public func startAIRecognitionForUnknownDevices() {
        startAIRecognition(for: unknownDevicesForAIRecognition, unknownOnly: true)
    }

    public func startAIRecognition(for device: DiscoveredNetworkDevice) {
        startAIRecognition(for: [device], unknownOnly: false)
    }

    public func cancelAIRecognition() {
        guard isAIRecognitionRunning else { return }
        aiRecognitionTask?.cancel()
        aiRecognitionTask = nil
        aiRecognitionID = nil
        isAIRecognitionRunning = false
        let analyzingIdentities = aiRecognitionStates.compactMap { identity, state in
            state == .analyzing ? identity : nil
        }
        for identity in analyzingIdentities {
            aiRecognitionStates[identity] = .failed("AI recognition was cancelled.")
        }
    }

    private func startAIRecognition(
        for requestedDevices: [DiscoveredNetworkDevice],
        unknownOnly: Bool
    ) {
        guard !isAIRecognitionRunning, networkScanPhase != .scanning else { return }
        refreshOpenAIAPIKeyAvailability()
        guard hasOpenAIAPIKey else {
            aiRecognitionErrorDescription = AIRecognitionError.missingAPIKey.localizedDescription
            return
        }

        let devices = requestedDevices.filter {
            unknownOnly ? $0.isUnknownForAIRecognition : $0.isEligibleForAIRecognition
        }
        guard !devices.isEmpty else { return }
        let recognitionID = UUID()
        let generation = networkScanGeneration
        aiRecognitionID = recognitionID
        aiRecognitionCompletedCount = 0
        aiRecognitionTotalCount = devices.count
        aiRecognitionErrorDescription = nil
        isAIRecognitionRunning = true
        for device in devices {
            aiRecognitionStates[device.aiIdentity] = .analyzing
        }

        aiRecognitionTask = Task { [weak self] in
            guard let self else { return }
            let batches = AIRecognitionBatcher.batches(from: devices)

            for batch in batches {
                if Task.isCancelled { return }
                let mappings = Dictionary(uniqueKeysWithValues: batch.enumerated().map { offset, device in
                    ("item-\(self.aiRecognitionCompletedCount + offset + 1)", device.aiIdentity)
                })
                let inputs = batch.enumerated().map { offset, device in
                    AIRecognitionInput(
                        itemID: "item-\(self.aiRecognitionCompletedCount + offset + 1)",
                        device: device
                    )
                }

                do {
                    let recognitions = try await self.aiRecognitionProvider.recognize(inputs)
                    guard self.aiRecognitionID == recognitionID,
                          self.networkScanGeneration == generation,
                          !Task.isCancelled
                    else { return }
                    for recognition in recognitions {
                        guard let identity = mappings[recognition.itemID] else { continue }
                        if recognition.suggestedName.caseInsensitiveCompare("Unable to recognize") == .orderedSame {
                            self.aiRecognitionStates[identity] = .insufficient(recognition.limitations)
                        } else {
                            self.aiRecognitionStates[identity] = .recognized(recognition)
                        }
                    }
                    self.aiRecognitionCompletedCount += batch.count
                    self.persistDeviceHistory()
                } catch is CancellationError {
                    return
                } catch let error as AIRecognitionError {
                    guard self.aiRecognitionID == recognitionID else { return }
                    for identity in mappings.values {
                        if case .analyzing = self.aiRecognitionStates[identity] {
                            if case .refused(let reason) = error {
                                self.aiRecognitionStates[identity] = .refused(reason)
                            } else {
                                self.aiRecognitionStates[identity] = .failed(error.localizedDescription)
                            }
                        }
                    }
                    self.aiRecognitionErrorDescription = error.localizedDescription
                    break
                } catch {
                    guard self.aiRecognitionID == recognitionID else { return }
                    for identity in mappings.values {
                        self.aiRecognitionStates[identity] = .failed(error.localizedDescription)
                    }
                    self.aiRecognitionErrorDescription = error.localizedDescription
                    break
                }
            }

            if self.aiRecognitionID == recognitionID {
                self.isAIRecognitionRunning = false
                self.aiRecognitionTask = nil
                self.aiRecognitionID = nil
            }
        }
    }

    private func persistDeviceHistory() {
        for device in networkScanDevices {
            guard let macAddress = device.macAddress else { continue }
            let currentRecognition: DeviceAIRecognition?
            if case .recognized(let recognition) = aiRecognitionStates[device.aiIdentity] {
                currentRecognition = recognition
            } else {
                currentRecognition = persistedDeviceRecords[macAddress]?.aiRecognition
            }
            guard let record = PersistedDeviceRecord(
                device: device,
                aiRecognition: currentRecognition
            ) else { continue }
            persistedDeviceRecords[macAddress] = record
        }

        do {
            try deviceHistoryStore.save(persistedDeviceRecords)
            deviceHistoryRecordCount = persistedDeviceRecords.count
            deviceHistoryErrorDescription = nil
        } catch {
            deviceHistoryErrorDescription = error.localizedDescription
        }
    }

    public func startWiFiScanning(refreshInterval: TimeInterval = 30) {
        guard wifiScanTimerCancellable == nil else {
            return
        }

        refreshWiFiScan()
        wifiScanTimerCancellable = Timer
            .publish(every: max(5, refreshInterval), on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshWiFiScan()
            }
    }

    public func stopWiFiScanning() {
        wifiScanTimerCancellable?.cancel()
        wifiScanTimerCancellable = nil
    }

    public func refreshWiFiScan() {
        guard !isWiFiScanRefreshing else {
            return
        }

        wifiScanRefreshToken += 1
        isWiFiScanRefreshing = true
        wifiScanErrorDescription = nil

        Task.detached(priority: .userInitiated) {
            let result = Self.scanWiFiNetworks()
            await MainActor.run {
                self.isWiFiScanRefreshing = false
                switch result {
                case .success(let networks):
                    self.wifiScanResults = networks
                    self.lastWiFiScanAt = Date()
                    self.wifiScanErrorDescription = Self.wifiScanVisibilityWarning(for: networks)
                case .failure(let error):
                    self.wifiScanErrorDescription = error.localizedDescription
                }
            }
        }
    }

    private static func isVirtualTunnelInterface(named name: String) -> Bool {
        let normalizedName = name.lowercased()
        let virtualTunnelPrefixes = [
            "utun",
            "tun",
            "tap",
            "ppp",
            "ipsec",
            "wg",
            "tailscale",
            "zt",
            "vpn"
        ]

        return virtualTunnelPrefixes.contains { normalizedName.hasPrefix($0) }
    }

    public func startMonitoring() {
        guard timerCancellable == nil else {
            return
        }

        status = .running
        lastErrorDescription = nil
        timerCancellable = Timer
            .publish(every: samplingInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    public func stopMonitoring(resetValues: Bool = false) {
        timerCancellable?.cancel()
        timerCancellable = nil
        status = .stopped
        WidgetSnapshot.publish(
            download: downloadBytesPerSecond,
            upload: uploadBytesPerSecond,
            updatedAt: Date(),
            isRunning: false
        )

        if resetValues {
            downloadBytesPerSecond = 0
            uploadBytesPerSecond = 0
            maxDownloadBytesPerSecond = 0
            maxUploadBytesPerSecond = 0
            totalDownloadBytes = 0
            totalUploadBytes = 0
            runtime = 0
            previousSnapshot = nil
            lastUpdatedAt = nil
            startDate = Date()
            speedHistory.removeAll()
        }
    }

    nonisolated private static func scanWiFiNetworks() -> Result<[WiFiNetworkInfo], WiFiScanError> {
        let client = CWWiFiClient.shared()
        guard let interfaces = client.interfaces(), !interfaces.isEmpty else {
            return .failure(.noWiFiInterface)
        }

        let connectedSSID = interfaces.compactMap { $0.ssid() }.first
        let connectedBSSID = interfaces.compactMap { $0.bssid() }.first
        let routerIPAddress = defaultRouterIPAddress()

        var mergedNetworks: [String: WiFiNetworkInfo] = [:]

        for interface in interfaces {
            do {
                let scannedNetworks = try interface.scanForNetworks(withName: nil, includeHidden: false)
                for network in scannedNetworks {
                    let ssid = displayName(for: network, connectedSSID: connectedSSID)
                    let bssid = network.bssid
                    let wlanChannel = network.wlanChannel
                    let channel = wlanChannel?.channelNumber ?? 0
                    let band = band(for: wlanChannel)
                    let isConnected = (bssid != nil && bssid == connectedBSSID)
                        || (bssid == nil && ssid == connectedSSID)
                    let info = WiFiNetworkInfo(
                        ssid: ssid,
                        bssid: bssid,
                        rssi: network.rssiValue,
                        signalPercentage: signalPercentage(for: network.rssiValue),
                        band: band,
                        channel: channel,
                        channelWidth: channelWidthDescription(for: wlanChannel?.channelWidth),
                        isConnected: isConnected,
                        securityDescription: securityDescription(for: network),
                        routerGeneration: routerGeneration(for: network),
                        routerIPAddress: isConnected ? routerIPAddress : nil,
                        vendorName: OUIVendorLookup.shared.vendorName(for: bssid),
                        countryCode: normalizedCountryCode(network.countryCode)
                    )

                    let key = bssid ?? "\(ssid)-\(channel)-\(network.rssiValue)"
                    if let existing = mergedNetworks[key], existing.rssi >= info.rssi {
                        continue
                    }
                    mergedNetworks[key] = info
                }
            } catch {
                Self.logger.error("Wi-Fi scan failed on \(interface.interfaceName ?? "unknown", privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        let networks = addChannelCongestionDetails(to: Array(mergedNetworks.values)).sorted {
            if $0.isConnected != $1.isConnected {
                return $0.isConnected
            }
            return $0.rssi > $1.rssi
        }

        if networks.isEmpty {
            return .failure(.noNetworksFound)
        }

        return .success(networks)
    }

    nonisolated private static func defaultRouterIPAddress() -> String? {
        guard let store = SCDynamicStoreCreate(
            nil,
            "MacSpeedMonitor.RouterLookup" as CFString,
            nil,
            nil
        ),
        let ipv4State = SCDynamicStoreCopyValue(
            store,
            "State:/Network/Global/IPv4" as CFString
        ) as? [String: Any],
        let router = ipv4State["Router"] as? String,
        !router.isEmpty
        else {
            return nil
        }

        var address = in_addr()
        guard router.withCString({ inet_pton(AF_INET, $0, &address) }) == 1 else {
            return nil
        }
        return router
    }

    nonisolated private static func displayName(for network: CWNetwork, connectedSSID: String?) -> String {
        if let ssid = network.ssid, !ssid.isEmpty {
            return ssid
        }

        if let ssidData = network.ssidData {
            if let utf8SSID = String(data: ssidData, encoding: .utf8), !utf8SSID.isEmpty {
                return utf8SSID
            }

            if let latinSSID = String(data: ssidData, encoding: .isoLatin1), !latinSSID.isEmpty {
                return latinSSID
            }
        }

        if let connectedSSID, !connectedSSID.isEmpty, network.bssid == nil {
            return connectedSSID
        }

        return "Hidden Network"
    }

    nonisolated private static func wifiScanVisibilityWarning(for networks: [WiFiNetworkInfo]) -> String? {
        guard !networks.isEmpty, networks.allSatisfy({ $0.ssid == "Hidden Network" }) else {
            return nil
        }

        return "macOS is hiding Wi-Fi names from this app. Enable Location Services permission for MacSpeedMonitor to allow CoreWLAN to return SSID and BSSID details."
    }

    nonisolated private static func signalPercentage(for rssi: Int) -> Int {
        let clampedRSSI = min(max(rssi, -95), -35)
        return Int(round(Double(clampedRSSI + 95) / 60.0 * 100.0))
    }

    nonisolated private static func channelWidthDescription(for width: CWChannelWidth?) -> String {
        guard let width else {
            return "Unknown"
        }

        switch width {
        case .width20MHz:
            return "20 MHz"
        case .width40MHz:
            return "40 MHz"
        case .width80MHz:
            return "80 MHz"
        case .width160MHz:
            return "160 MHz"
        default:
            return "Unknown"
        }
    }

    nonisolated private static func routerGeneration(for network: CWNetwork) -> String {
        if network.supportsPHYMode(.mode11be) {
            return "Wi-Fi 7"
        }
        if network.supportsPHYMode(.mode11ax) {
            return "Wi-Fi 6"
        }
        if network.supportsPHYMode(.mode11ac) {
            return "Wi-Fi 5"
        }
        if network.supportsPHYMode(.mode11n) {
            return "Wi-Fi 4"
        }
        if network.supportsPHYMode(.mode11g) {
            return "Wi-Fi 3"
        }
        if network.supportsPHYMode(.mode11a) {
            return "Wi-Fi 2"
        }
        if network.supportsPHYMode(.mode11b) {
            return "Wi-Fi 1"
        }
        return "Unknown"
    }

    nonisolated private static func securityDescription(for network: CWNetwork) -> String {
        if network.supportsSecurity(.wpa3Personal) {
            return "WPA3 Personal"
        }
        if network.supportsSecurity(.wpa3Enterprise) {
            return "WPA3 Enterprise"
        }
        if network.supportsSecurity(.wpa3Transition) {
            return "WPA3/WPA2"
        }
        if network.supportsSecurity(.wpa2Personal) {
            return "WPA2 Personal"
        }
        if network.supportsSecurity(.wpa2Enterprise) {
            return "WPA2 Enterprise"
        }
        if network.supportsSecurity(.wpaPersonal) {
            return "WPA Personal"
        }
        if network.supportsSecurity(.wpaEnterprise) {
            return "WPA Enterprise"
        }
        if network.supportsSecurity(.OWE) {
            return "OWE"
        }
        if network.supportsSecurity(.none) {
            return "Open"
        }
        if network.supportsSecurity(.WEP) {
            return "WEP"
        }
        return "Unknown"
    }

    nonisolated private static func normalizedCountryCode(_ countryCode: String?) -> String? {
        guard let countryCode = countryCode?.trimmingCharacters(in: .whitespacesAndNewlines),
              !countryCode.isEmpty
        else {
            return nil
        }
        return countryCode.uppercased()
    }

    nonisolated private static func addChannelCongestionDetails(to networks: [WiFiNetworkInfo]) -> [WiFiNetworkInfo] {
        networks.map { network in
            let sameChannelCount = networks.filter { other in
                other.id != network.id
                    && other.band == network.band
                    && other.channel == network.channel
            }.count

            let overlappingChannelCount = networks.filter { other in
                other.id != network.id
                    && other.band == network.band
                    && other.channel != network.channel
                    && channelsOverlap(network, other)
            }.count

            return network.withCongestionDetails(
                sameChannelAPCount: sameChannelCount,
                overlappingChannelAPCount: overlappingChannelCount
            )
        }
    }

    nonisolated private static func channelsOverlap(_ lhs: WiFiNetworkInfo, _ rhs: WiFiNetworkInfo) -> Bool {
        guard let lhsRange = channelFrequencyRange(for: lhs),
              let rhsRange = channelFrequencyRange(for: rhs)
        else {
            return false
        }

        return lhsRange.lowerBound < rhsRange.upperBound
            && rhsRange.lowerBound < lhsRange.upperBound
    }

    nonisolated private static func channelFrequencyRange(for network: WiFiNetworkInfo) -> ClosedRange<Double>? {
        guard let center = centerFrequencyMHz(for: network.channel, band: network.band) else {
            return nil
        }

        let halfWidth = max(10.0, channelWidthMHz(from: network.channelWidth) / 2.0)
        return (center - halfWidth)...(center + halfWidth)
    }

    nonisolated private static func centerFrequencyMHz(for channel: Int, band: WiFiNetworkInfo.Band) -> Double? {
        guard channel > 0 else {
            return nil
        }

        switch band {
        case .twoPointFourGHz:
            if channel == 14 {
                return 2484
            }
            return 2407 + Double(channel * 5)
        case .fiveGHz:
            return 5000 + Double(channel * 5)
        case .sixGHz:
            return 5950 + Double(channel * 5)
        case .unknown:
            return nil
        }
    }

    nonisolated private static func channelWidthMHz(from description: String) -> Double {
        if description.hasPrefix("160") {
            return 160
        }
        if description.hasPrefix("80") {
            return 80
        }
        if description.hasPrefix("40") {
            return 40
        }
        return 20
    }

    nonisolated private static func band(for channel: CWChannel?) -> WiFiNetworkInfo.Band {
        guard let channel else {
            return .unknown
        }

        switch channel.channelBand {
        case .band2GHz:
            return .twoPointFourGHz
        case .band5GHz:
            return .fiveGHz
        case .band6GHz:
            return .sixGHz
        default:
            let number = channel.channelNumber
            if number >= 1 && number <= 14 {
                return .twoPointFourGHz
            }
            if number >= 32 && number <= 177 {
                return .fiveGHz
            }
            if number >= 1 {
                return .sixGHz
            }
            return .unknown
        }
    }

    private func getWiFiLinkSpeed(interfaceName: String) -> Double? {
        let client = CWWiFiClient.shared()
        if let interface = client.interface(withName: interfaceName) {
            let rate = interface.transmitRate()
            if rate > 0 {
                return rate
            }
        }
        return nil
    }

    private func getEthernetLinkSpeed(interfaceName: String) -> Double? {
        let matchingDict = IOBSDNameMatching(kIOMainPortDefault, 0, interfaceName)
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service) }
            
            var parent: io_registry_entry_t = 0
            if IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent) == KERN_SUCCESS {
                defer { IOObjectRelease(parent) }
                
                if let speedRef = IORegistryEntryCreateCFProperty(parent, "current-speed" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
                   let speedNum = speedRef as? NSNumber {
                    let speedInBps = speedNum.doubleValue
                    if speedInBps > 0 {
                        return speedInBps / 1_000_000.0
                    }
                }
                
                if let speedRef = IORegistryEntryCreateCFProperty(parent, "max-speed" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
                   let speedNum = speedRef as? NSNumber {
                    let speedInBps = speedNum.doubleValue
                    if speedInBps > 0 {
                        return speedInBps / 1_000_000.0
                    }
                }
            }
            
            service = IOIteratorNext(iterator)
        }
        return nil
    }

    private func getLinkSpeed(interfaceName: String) -> String? {
        if let wifiSpeed = getWiFiLinkSpeed(interfaceName: interfaceName) {
            return String(format: "%.0f Mbps (Wi-Fi)", wifiSpeed)
        }
        if let ethSpeed = getEthernetLinkSpeed(interfaceName: interfaceName) {
            return String(format: "%.0f Mbps (Wired)", ethSpeed)
        }
        return nil
    }

    public func getNetworkInterfaces() -> [NetworkInterfaceInfo] {
        var interfaces = [NetworkInterfaceInfo]()
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else {
            return []
        }
        defer { freeifaddrs(pointer) }

        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let node = current {
            let interface = node.pointee
            let name = String(cString: interface.ifa_name)
            let flags = Int32(interface.ifa_flags)

            let isUp = (flags & IFF_UP) != 0
            let isRunning = (flags & IFF_RUNNING) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            let isVirtualTunnel = Self.isVirtualTunnelInterface(named: name)
            let isCommonHardwareInterface = name.hasPrefix("en")

            var addressString: String? = nil
            var familyString = "Unknown"

            if let addr = interface.ifa_addr {
                let family = addr.pointee.sa_family
                if family == UInt8(AF_INET) {
                    familyString = "IPv4"
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                        addressString = hostname.withUnsafeBufferPointer { ptr in
                            ptr.baseAddress.map { String(cString: $0) }
                        }
                    }
                } else if family == UInt8(AF_INET6) {
                    familyString = "IPv6"
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                        addressString = hostname.withUnsafeBufferPointer { ptr in
                            ptr.baseAddress.map { String(cString: $0) }
                        }
                    }
                } else if family == UInt8(AF_LINK) {
                    familyString = "Link"
                }
            }

            // Only display active connections, exclude loopbacks
            if (familyString == "IPv4" || familyString == "IPv6")
                && isUp
                && isRunning
                && !isLoopback
                && !isVirtualTunnel
                && isCommonHardwareInterface {
                var linkSpeed: String? = nil
                var txRate: Double? = nil
                var rxRate: Double? = nil
                var wifiMode: String? = nil
                
                linkSpeed = getLinkSpeed(interfaceName: name)
                
                let client = CWWiFiClient.shared()
                if let wifiInterface = client.interface(withName: name) {
                    let tx = wifiInterface.transmitRate()
                    if tx > 0 { txRate = tx }
                    // CoreWLAN provides a single negotiated PHY link rate (Tx).
                    // Rx is symmetric in 802.11, so we display txRate as the link rate.
                    rxRate = txRate
                    
                    let mode = wifiInterface.activePHYMode()
                    switch mode {
                    case .mode11a: wifiMode = "Wi-Fi 2"
                    case .mode11b: wifiMode = "Wi-Fi 1"
                    case .mode11g: wifiMode = "Wi-Fi 3"
                    case .mode11n: wifiMode = "Wi-Fi 4"
                    case .mode11ac: wifiMode = "Wi-Fi 5"
                    case .mode11ax: wifiMode = "Wi-Fi 6"
                    case .mode11be: wifiMode = "Wi-Fi 7"
                    default: wifiMode = "Wi-Fi"
                    }
                }
                
                interfaces.append(NetworkInterfaceInfo(
                    name: name,
                    family: familyString,
                    address: addressString,
                    isUp: isUp,
                    isRunning: isRunning,
                    isLoopback: isLoopback,
                    linkSpeed: linkSpeed,
                    txRate: txRate,
                    rxRate: rxRate,
                    wifiMode: wifiMode
                ))
            }

            current = interface.ifa_next
        }
        let preferredByInterface = Dictionary(grouping: interfaces, by: \.name).compactMap { _, addresses in
            addresses.first(where: { $0.family == "IPv4" }) ?? addresses.first
        }
        return preferredByInterface.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func tick() {
        runtime = Date().timeIntervalSince(startDate)
        switch Self.captureSnapshot() {
        case .failure(let error):
            recordFailure(error)
            return
        case .success(let current):
            updateSpeeds(current: current)
        }
    }

    private func updateSpeeds(current: InterfaceSnapshot) {
        guard let previous = previousSnapshot else {
            previousSnapshot = current
            downloadBytesPerSecond = 0
            uploadBytesPerSecond = 0
            lastUpdatedAt = current.timestamp
            status = .running
            consecutiveFailureCount = 0
            lastErrorDescription = nil
            return
        }

        let deltaTime = current.timestamp.timeIntervalSince(previous.timestamp)
        guard deltaTime > 0 else {
            previousSnapshot = current
            return
        }

        let downloadDiff = current.bytesReceived >= previous.bytesReceived
            ? current.bytesReceived - previous.bytesReceived
            : 0
        let uploadDiff = current.bytesSent >= previous.bytesSent
            ? current.bytesSent - previous.bytesSent
            : 0

        if current.bytesReceived < previous.bytesReceived || current.bytesSent < previous.bytesSent {
            Self.logger.warning("Detected interface counter reset; resetting one tick to avoid invalid negative throughput.")
        }

        downloadBytesPerSecond = Double(downloadDiff) / deltaTime
        uploadBytesPerSecond = Double(uploadDiff) / deltaTime
        WidgetSnapshot.publish(
            download: downloadBytesPerSecond,
            upload: uploadBytesPerSecond,
            updatedAt: current.timestamp,
            isRunning: true
        )
        maxDownloadBytesPerSecond = max(maxDownloadBytesPerSecond, downloadBytesPerSecond)
        maxUploadBytesPerSecond = max(maxUploadBytesPerSecond, uploadBytesPerSecond)
        totalDownloadBytes += downloadDiff
        totalUploadBytes += uploadDiff
        previousSnapshot = current
        lastUpdatedAt = current.timestamp
        status = .running
        consecutiveFailureCount = 0
        lastErrorDescription = nil
        
        let durationSeconds = UserDefaults.standard.integer(forKey: "historyDurationSeconds")
        let limit = durationSeconds == 0 ? 60 : durationSeconds
        let historyLimit = max(5, Int(Double(limit) / samplingInterval))
        
        let point = SpeedHistoryPoint(timestamp: current.timestamp, downloadSpeed: downloadBytesPerSecond, uploadSpeed: uploadBytesPerSecond)
        speedHistory.append(point)
        while speedHistory.count > historyLimit {
            speedHistory.removeFirst()
        }
    }

    private func recordFailure(_ error: SnapshotError) {
        consecutiveFailureCount += 1
        lastErrorDescription = error.localizedDescription
        status = .degraded
        Self.logger.error("Failed to capture network snapshot (\(self.consecutiveFailureCount)): \(error.localizedDescription, privacy: .public)")

        if consecutiveFailureCount >= 3 {
            // Drop stale baseline to recover quickly after transient getifaddrs failures.
            previousSnapshot = nil
            downloadBytesPerSecond = 0
            uploadBytesPerSecond = 0
        }
    }

    private static func captureSnapshot() -> Result<InterfaceSnapshot, SnapshotError> {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        let statusCode = getifaddrs(&pointer)
        guard statusCode == 0, let first = pointer else {
            let errorCode = errno
            return .failure(.getifaddrsFailed(errorCode: errorCode))
        }
        defer { freeifaddrs(pointer) }

        var totalSent: UInt64 = 0
        var totalReceived: UInt64 = 0
        var observedInterfaces = 0

        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let node = current {
            let interface = node.pointee
            let flags = Int32(interface.ifa_flags)

            let isUp = (flags & IFF_UP) != 0
            let isRunning = (flags & IFF_RUNNING) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            if isUp, isRunning, !isLoopback,
               interface.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
               let dataPointer = interface.ifa_data {
                let data = dataPointer.assumingMemoryBound(to: if_data.self).pointee
                totalSent += UInt64(data.ifi_obytes)
                totalReceived += UInt64(data.ifi_ibytes)
                observedInterfaces += 1
            }

            current = interface.ifa_next
        }

        guard observedInterfaces > 0 else {
            return .failure(.noUsableInterfaces)
        }

        return .success(InterfaceSnapshot(timestamp: Date(), bytesSent: totalSent, bytesReceived: totalReceived))
    }
}

private enum WiFiScanError: LocalizedError {
    case noWiFiInterface
    case noNetworksFound

    var errorDescription: String? {
        switch self {
        case .noWiFiInterface:
            return "No Wi-Fi interface is available."
        case .noNetworksFound:
            return "No nearby Wi-Fi networks were found."
        }
    }
}

public enum MonitorStatus: String {
    case idle
    case running
    case degraded
    case stopped
}

public struct SpeedHistoryPoint: Identifiable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let downloadSpeed: Double
    public let uploadSpeed: Double
    
    public init(id: UUID = UUID(), timestamp: Date, downloadSpeed: Double, uploadSpeed: Double) {
        self.id = id
        self.timestamp = timestamp
        self.downloadSpeed = downloadSpeed
        self.uploadSpeed = uploadSpeed
    }
}

private struct InterfaceSnapshot {
    let timestamp: Date
    let bytesSent: UInt64
    let bytesReceived: UInt64
}

private enum SnapshotError: LocalizedError {
    case getifaddrsFailed(errorCode: Int32)
    case noUsableInterfaces

    var errorDescription: String? {
        switch self {
        case .getifaddrsFailed(let errorCode):
            return "Failed to read network interfaces (errno \(errorCode))."
        case .noUsableInterfaces:
            return "No active non-loopback network interfaces were found."
        }
    }
}
