import Foundation
import Combine
import Darwin
import OSLog

#if os(macOS)
import CoreWLAN
import IOKit
import IOKit.network
#endif

@MainActor
public final class NetworkSpeedMonitor: ObservableObject {
    @Published public private(set) var downloadBytesPerSecond: Double = 0
    @Published public private(set) var uploadBytesPerSecond: Double = 0
    @Published public private(set) var totalDownloadBytes: UInt64 = 0
    @Published public private(set) var totalUploadBytes: UInt64 = 0
    @Published public private(set) var runtime: TimeInterval = 0
    @Published public private(set) var status: MonitorStatus = .idle
    @Published public private(set) var lastErrorDescription: String?
    @Published public private(set) var lastUpdatedAt: Date?
    @Published public private(set) var speedHistory: [SpeedHistoryPoint] = []

    private var timerCancellable: AnyCancellable?
    private var previousSnapshot: InterfaceSnapshot?
    private let samplingInterval: TimeInterval
    private var consecutiveFailureCount = 0
    private var startDate = Date()

    private static let logger = Logger(subsystem: "MacSpeedMonitor", category: "NetworkSpeedMonitor")

    public init(samplingInterval: TimeInterval = 1.0) {
        self.samplingInterval = max(0.2, samplingInterval)
        if case .success(let snapshot) = Self.captureSnapshot() {
            previousSnapshot = snapshot
        }
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

        if resetValues {
            downloadBytesPerSecond = 0
            uploadBytesPerSecond = 0
            totalDownloadBytes = 0
            totalUploadBytes = 0
            runtime = 0
            previousSnapshot = nil
            lastUpdatedAt = nil
            startDate = Date()
            speedHistory.removeAll()
        }
    }

#if os(macOS)
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
#endif

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

            if familyString == "IPv4" || familyString == "IPv6" {
                var linkSpeed: String? = nil
                #if os(macOS)
                linkSpeed = getLinkSpeed(interfaceName: name)
                #endif
                
                interfaces.append(NetworkInterfaceInfo(
                    name: name,
                    family: familyString,
                    address: addressString,
                    isUp: isUp,
                    isRunning: isRunning,
                    isLoopback: isLoopback,
                    linkSpeed: linkSpeed
                ))
            }

            current = interface.ifa_next
        }
        return interfaces
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
        totalDownloadBytes += downloadDiff
        totalUploadBytes += uploadDiff
        previousSnapshot = current
        lastUpdatedAt = current.timestamp
        status = .running
        consecutiveFailureCount = 0
        lastErrorDescription = nil
        
        let point = SpeedHistoryPoint(timestamp: current.timestamp, downloadSpeed: downloadBytesPerSecond, uploadSpeed: uploadBytesPerSecond)
        speedHistory.append(point)
        if speedHistory.count > 30 {
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
