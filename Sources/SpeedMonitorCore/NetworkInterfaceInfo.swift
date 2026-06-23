import Foundation
import Darwin
import SystemConfiguration
import dnssd

public struct NetworkInterfaceInfo: Identifiable, Hashable {
    public var id: String {
        return "\(name)-\(family)-\(address ?? "")"
    }
    public let name: String
    public let family: String
    public let address: String?
    public let isUp: Bool
    public let isRunning: Bool
    public let isLoopback: Bool
    public let linkSpeed: String?
    public let txRate: Double?
    public let rxRate: Double?
    public let wifiMode: String?

    public init(name: String, family: String, address: String?, isUp: Bool, isRunning: Bool, isLoopback: Bool, linkSpeed: String?, txRate: Double?, rxRate: Double?, wifiMode: String?) {
        self.name = name
        self.family = family
        self.address = address
        self.isUp = isUp
        self.isRunning = isRunning
        self.isLoopback = isLoopback
        self.linkSpeed = linkSpeed
        self.txRate = txRate
        self.rxRate = rxRate
        self.wifiMode = wifiMode
    }
}

// MARK: - Local Network Scanner

public struct DiscoveredNetworkDevice: Codable, Sendable, Identifiable, Hashable {
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

    public init?(
        ipv4Address: String,
        hostname: String? = nil,
        macAddress: String? = nil,
        vendorName: String? = nil,
        responseTimeMilliseconds: Double? = nil,
        isRouter: Bool = false,
        isLocalDevice: Bool = false,
        lastSeenAt: Date = Date(),
        isStale: Bool = false
    ) {
        guard IPv4AddressValue(ipv4Address) != nil else { return nil }
        self.ipv4Address = ipv4Address
        self.hostname = hostname?.nilIfEmpty
        self.macAddress = Self.normalizedMACAddress(macAddress)
        self.vendorName = vendorName?.nilIfEmpty
        self.responseTimeMilliseconds = responseTimeMilliseconds
        self.isRouter = isRouter
        self.isLocalDevice = isLocalDevice
        self.lastSeenAt = lastSeenAt
        self.isStale = isStale
    }

    public var displayName: String {
        hostname ?? (isRouter ? "Router" : (isLocalDevice ? "This Mac" : "Unknown Device"))
    }

    static func normalizedMACAddress(_ value: String?) -> String? {
        guard let value else { return nil }
        let hex = value.uppercased().filter(\.isHexDigit)
        guard hex.count == 12 else { return nil }
        return stride(from: 0, to: 12, by: 2)
            .map { index in
                let start = hex.index(hex.startIndex, offsetBy: index)
                let end = hex.index(start, offsetBy: 2)
                return String(hex[start..<end])
            }
            .joined(separator: ":")
    }
}

public struct NetworkScanRequest: Sendable, Equatable {
    public let interfaceName: String
    public let localIPv4Address: String
    public let prefixLength: Int
    public let routerIPv4Address: String?
    public let networkAddress: String
    public let broadcastAddress: String
    public let candidateHostAddresses: [String]
    public let localMACAddress: String?

    public static func make(
        interfaceName: String,
        address: String,
        netmask: String,
        routerAddress: String? = nil,
        localMACAddress: String? = nil
    ) throws -> NetworkScanRequest {
        guard !interfaceName.isEmpty else { throw NetworkScanError.noActiveInterface }
        guard let addressValue = IPv4AddressValue(address), addressValue.isPrivate else {
            throw NetworkScanError.noPrivateIPv4Network
        }
        guard let maskValue = IPv4AddressValue(netmask),
              let prefixLength = maskValue.contiguousPrefixLength,
              (1...30).contains(prefixLength)
        else {
            throw NetworkScanError.invalidSubnet
        }

        let totalAddressCount = UInt64(1) << UInt64(32 - prefixLength)
        guard totalAddressCount <= 256 else { throw NetworkScanError.oversizedSubnet }

        let networkValue = addressValue.rawValue & maskValue.rawValue
        let broadcastValue = networkValue | ~maskValue.rawValue
        let candidates = ((networkValue + 1)..<broadcastValue).map {
            IPv4AddressValue(rawValue: $0).description
        }

        let normalizedRouter = routerAddress.flatMap { candidate -> String? in
            guard let value = IPv4AddressValue(candidate),
                  value.rawValue > networkValue,
                  value.rawValue < broadcastValue
            else { return nil }
            return value.description
        }

        return NetworkScanRequest(
            interfaceName: interfaceName,
            localIPv4Address: addressValue.description,
            prefixLength: prefixLength,
            routerIPv4Address: normalizedRouter,
            networkAddress: IPv4AddressValue(rawValue: networkValue).description,
            broadcastAddress: IPv4AddressValue(rawValue: broadcastValue).description,
            candidateHostAddresses: candidates,
            localMACAddress: DiscoveredNetworkDevice.normalizedMACAddress(localMACAddress)
        )
    }
}

public enum NetworkScanError: LocalizedError, Sendable, Equatable {
    case noActiveInterface
    case noPrivateIPv4Network
    case invalidSubnet
    case oversizedSubnet
    case socketUnavailable(Int32)
    case networkChanged

    public var errorDescription: String? {
        switch self {
        case .noActiveInterface:
            return "Connect to an active Wi-Fi or Ethernet network before scanning."
        case .noPrivateIPv4Network:
            return "The active connection does not have a private IPv4 address that can be scanned."
        case .invalidSubnet:
            return "The current network's subnet information could not be interpreted safely."
        case .oversizedSubnet:
            return "This network contains more than 256 addresses. Network Scanner v1 supports networks up to /24."
        case .socketUnavailable(let code):
            return "macOS did not allow local-network discovery (error \(code)). Check the app's network access and try again."
        case .networkChanged:
            return "The active network changed during the scan. Start a new scan on the current network."
        }
    }
}

public enum NetworkScanEvent: Sendable {
    case started(totalTargets: Int)
    case device(DiscoveredNetworkDevice)
    case progress(completedTargets: Int, discoveredDevices: Int)
    case warning(String)
    case completed(Date)
}

public enum NetworkScanPhase: Sendable, Equatable {
    case idle
    case scanning
    case completed
    case cancelled
    case failed(String)
}

struct OpenPort: Sendable, Equatable, Hashable, Identifiable {
    let port: UInt16
    let serviceName: String

    var id: UInt16 { port }
    var displayName: String { "\(port) \(serviceName)" }
}

enum DevicePortScanState: Sendable, Equatable {
    case scanning
    case completed([OpenPort])
    case failed(String)

    var isScanning: Bool {
        if case .scanning = self { return true }
        return false
    }
}

struct CommonPortScanner: Sendable {
    static let commonPorts: [OpenPort] = [
        OpenPort(port: 20, serviceName: "FTP Data"),
        OpenPort(port: 21, serviceName: "FTP"),
        OpenPort(port: 22, serviceName: "SSH"),
        OpenPort(port: 23, serviceName: "Telnet"),
        OpenPort(port: 25, serviceName: "SMTP"),
        OpenPort(port: 53, serviceName: "DNS"),
        OpenPort(port: 80, serviceName: "HTTP"),
        OpenPort(port: 110, serviceName: "POP3"),
        OpenPort(port: 111, serviceName: "RPC"),
        OpenPort(port: 135, serviceName: "MS RPC"),
        OpenPort(port: 139, serviceName: "NetBIOS"),
        OpenPort(port: 143, serviceName: "IMAP"),
        OpenPort(port: 443, serviceName: "HTTPS"),
        OpenPort(port: 445, serviceName: "SMB"),
        OpenPort(port: 515, serviceName: "LPD"),
        OpenPort(port: 548, serviceName: "AFP"),
        OpenPort(port: 631, serviceName: "IPP"),
        OpenPort(port: 993, serviceName: "IMAPS"),
        OpenPort(port: 995, serviceName: "POP3S"),
        OpenPort(port: 1883, serviceName: "MQTT"),
        OpenPort(port: 2049, serviceName: "NFS"),
        OpenPort(port: 3000, serviceName: "Web App"),
        OpenPort(port: 3306, serviceName: "MySQL"),
        OpenPort(port: 3389, serviceName: "Remote Desktop"),
        OpenPort(port: 5000, serviceName: "Web/AirPlay"),
        OpenPort(port: 5357, serviceName: "Web Services"),
        OpenPort(port: 5432, serviceName: "PostgreSQL"),
        OpenPort(port: 5900, serviceName: "VNC"),
        OpenPort(port: 8000, serviceName: "Web App"),
        OpenPort(port: 8080, serviceName: "HTTP Alt"),
        OpenPort(port: 8443, serviceName: "HTTPS Alt"),
        OpenPort(port: 8883, serviceName: "MQTTS"),
        OpenPort(port: 9100, serviceName: "Printer"),
        OpenPort(port: 62078, serviceName: "Apple Device"),
    ]

    private let timeoutMilliseconds: Int32
    private let maximumConcurrentProbes: Int
    private let probePort: @Sendable (String, UInt16, Int32) -> Bool

    init(
        timeoutMilliseconds: Int32 = 350,
        maximumConcurrentProbes: Int = 12,
        probePort: (@Sendable (String, UInt16, Int32) -> Bool)? = nil
    ) {
        self.timeoutMilliseconds = max(50, timeoutMilliseconds)
        self.maximumConcurrentProbes = max(1, maximumConcurrentProbes)
        self.probePort = probePort ?? Self.probe
    }

    nonisolated func scan(address: String) async throws -> [OpenPort] {
        var openPorts: [OpenPort] = []
        for batchStart in stride(from: 0, to: Self.commonPorts.count, by: maximumConcurrentProbes) {
            try Task.checkCancellation()
            let batchEnd = min(batchStart + maximumConcurrentProbes, Self.commonPorts.count)
            let batch = Self.commonPorts[batchStart..<batchEnd]
            try await withThrowingTaskGroup(of: OpenPort?.self) { group in
                for candidate in batch {
                    group.addTask {
                        try Task.checkCancellation()
                        return probePort(address, candidate.port, timeoutMilliseconds) ? candidate : nil
                    }
                }
                for try await result in group {
                    if let result { openPorts.append(result) }
                }
            }
        }
        return openPorts.sorted { $0.port < $1.port }
    }

    nonisolated private static func probe(address: String, port: UInt16, timeoutMilliseconds: Int32) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        let existingFlags = fcntl(descriptor, F_GETFL, 0)
        guard existingFlags >= 0,
              fcntl(descriptor, F_SETFL, existingFlags | O_NONBLOCK) == 0
        else { return false }

        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = port.bigEndian
        guard address.withCString({ inet_pton(AF_INET, $0, &destination.sin_addr) }) == 1 else {
            return false
        }

        let connectionResult = withUnsafePointer(to: &destination) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if connectionResult == 0 { return true }
        guard errno == EINPROGRESS else { return false }

        var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
        guard poll(&pollDescriptor, 1, timeoutMilliseconds) > 0 else { return false }

        var socketError: Int32 = 0
        var errorLength = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &socketError, &errorLength) == 0 else {
            return false
        }
        return socketError == 0
    }
}

protocol NetworkScanning: Sendable {
    func scan(request: NetworkScanRequest) -> AsyncThrowingStream<NetworkScanEvent, Error>
}

struct LocalNetworkScanner: NetworkScanning {
    private let maximumConcurrentProbes = 32

    func scan(request: NetworkScanRequest) -> AsyncThrowingStream<NetworkScanEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    let targets = request.candidateHostAddresses.filter { $0 != request.localIPv4Address }
                    continuation.yield(.started(totalTargets: targets.count))

                    var discoveredAddresses = Set<String>()
                    let now = Date()
                    if let localDevice = DiscoveredNetworkDevice(
                        ipv4Address: request.localIPv4Address,
                        hostname: Host.current().localizedName,
                        macAddress: request.localMACAddress,
                        vendorName: Self.vendorName(for: request.localMACAddress),
                        isLocalDevice: true,
                        lastSeenAt: now
                    ) {
                        discoveredAddresses.insert(localDevice.ipv4Address)
                        continuation.yield(.device(localDevice))
                    }

                    if let routerAddress = request.routerIPv4Address,
                       routerAddress != request.localIPv4Address,
                       let router = DiscoveredNetworkDevice(
                           ipv4Address: routerAddress,
                           isRouter: true,
                           lastSeenAt: now
                       ) {
                        discoveredAddresses.insert(router.ipv4Address)
                        continuation.yield(.device(router))
                    }

                    var completedTargets = 0
                    for batchStart in stride(from: 0, to: targets.count, by: maximumConcurrentProbes) {
                        try Task.checkCancellation()
                        let batchEnd = min(batchStart + maximumConcurrentProbes, targets.count)
                        let batch = Array(targets[batchStart..<batchEnd])

                        try await withThrowingTaskGroup(of: ProbeResult.self) { group in
                            for (offset, address) in batch.enumerated() {
                                group.addTask {
                                    try Task.checkCancellation()
                                    return try Self.probe(
                                        address: address,
                                        interfaceName: request.interfaceName,
                                        sequence: UInt16(truncatingIfNeeded: batchStart + offset)
                                    )
                                }
                            }

                            for try await result in group {
                                try Task.checkCancellation()
                                completedTargets += 1
                                if result.isReachable {
                                    discoveredAddresses.insert(result.address)
                                    if let device = DiscoveredNetworkDevice(
                                        ipv4Address: result.address,
                                        hostname: Self.resolveHostname(
                                            for: result.address,
                                            interfaceName: request.interfaceName
                                        ),
                                        macAddress: result.macAddress,
                                        vendorName: Self.vendorName(for: result.macAddress),
                                        responseTimeMilliseconds: result.responseTimeMilliseconds,
                                        isRouter: result.address == request.routerIPv4Address,
                                        lastSeenAt: Date()
                                    ) {
                                        continuation.yield(.device(device))
                                    }
                                }
                                continuation.yield(.progress(
                                    completedTargets: completedTargets,
                                    discoveredDevices: discoveredAddresses.count
                                ))
                            }
                        }
                    }

                    try Task.checkCancellation()
                    continuation.yield(.completed(Date()))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    nonisolated private static func probe(
        address: String,
        interfaceName: String,
        sequence: UInt16
    ) throws -> ProbeResult {
        let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard descriptor >= 0 else { throw NetworkScanError.socketUnavailable(errno) }
        defer { close(descriptor) }

        var interfaceIndex = if_nametoindex(interfaceName)
        if interfaceIndex > 0 {
            setsockopt(
                descriptor,
                IPPROTO_IP,
                IP_BOUND_IF,
                &interfaceIndex,
                socklen_t(MemoryLayout.size(ofValue: interfaceIndex))
            )
        }

        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        )

        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        guard address.withCString({ inet_pton(AF_INET, $0, &destination.sin_addr) }) == 1 else {
            return ProbeResult(address: address, responseTimeMilliseconds: nil)
        }

        var packet = [UInt8](repeating: 0, count: 16)
        packet[0] = 8
        packet[4] = UInt8(truncatingIfNeeded: getpid() >> 8)
        packet[5] = UInt8(truncatingIfNeeded: getpid())
        packet[6] = UInt8(sequence >> 8)
        packet[7] = UInt8(sequence & 0xFF)
        let timestamp = DispatchTime.now().uptimeNanoseconds
        withUnsafeBytes(of: timestamp.bigEndian) { bytes in
            packet.replaceSubrange(8..<16, with: bytes)
        }
        let checksum = icmpChecksum(packet)
        packet[2] = UInt8(checksum >> 8)
        packet[3] = UInt8(checksum & 0xFF)

        let startedAt = DispatchTime.now().uptimeNanoseconds
        let sent = packet.withUnsafeBytes { packetPointer in
            withUnsafePointer(to: &destination) { destinationPointer in
                destinationPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    sendto(
                        descriptor,
                        packetPointer.baseAddress,
                        packet.count,
                        0,
                        socketAddress,
                        socklen_t(MemoryLayout<sockaddr_in>.size)
                    )
                }
            }
        }
        guard sent == packet.count else {
            if errno == EPERM || errno == EACCES {
                throw NetworkScanError.socketUnavailable(errno)
            }
            return ProbeResult(address: address, responseTimeMilliseconds: nil)
        }

        var response = [UInt8](repeating: 0, count: 128)
        let responseCapacity = response.count
        var source = sockaddr_in()
        var sourceLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let received = response.withUnsafeMutableBytes { pointer in
            withUnsafeMutablePointer(to: &source) { sourcePointer in
                sourcePointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    recvfrom(
                        descriptor,
                        pointer.baseAddress,
                        responseCapacity,
                        0,
                        socketAddress,
                        &sourceLength
                    )
                }
            }
        }
        let containsIPv4Header = received >= 20 && response[0] >> 4 == 4
        let icmpOffset = containsIPv4Header ? Int(response[0] & 0x0F) * 4 : 0
        let replySequence = received >= icmpOffset + 8
            ? UInt16(response[icmpOffset + 6]) << 8 | UInt16(response[icmpOffset + 7])
            : UInt16.max
        guard received >= icmpOffset + 8,
              response[icmpOffset] == 0,
              source.sin_addr.s_addr == destination.sin_addr.s_addr,
              replySequence == sequence
        else {
            return ProbeResult(address: address, responseTimeMilliseconds: nil)
        }

        let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
        return ProbeResult(
            address: address,
            responseTimeMilliseconds: Double(elapsed) / 1_000_000,
            macAddress: neighborMACAddress(for: address)
        )
    }

    nonisolated private static func neighborMACAddress(for address: String) -> String? {
        guard let target = IPv4AddressValue(address) else { return nil }
        var mib = [Int32(CTL_NET), Int32(PF_ROUTE), 0, Int32(AF_INET), Int32(NET_RT_FLAGS), Int32(RTF_LLINFO)]
        var requiredLength = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &requiredLength, nil, 0) == 0,
              requiredLength > 0
        else { return nil }

        var buffer = [UInt8](repeating: 0, count: requiredLength)
        let status = buffer.withUnsafeMutableBytes { bytes in
            sysctl(&mib, UInt32(mib.count), bytes.baseAddress, &requiredLength, nil, 0)
        }
        guard status == 0 else { return nil }

        var messageOffset = 0
        while messageOffset + MemoryLayout<rt_msghdr2>.size <= requiredLength {
            let header = buffer.withUnsafeBytes {
                $0.loadUnaligned(fromByteOffset: messageOffset, as: rt_msghdr2.self)
            }
            let messageLength = Int(header.rtm_msglen)
            guard messageLength > 0, messageOffset + messageLength <= requiredLength else { break }

            var socketAddressOffset = messageOffset + MemoryLayout<rt_msghdr2>.size
            var destination: UInt32?
            var macAddress: String?

            for addressIndex in 0..<Int(RTAX_MAX) where (header.rtm_addrs & (1 << Int32(addressIndex))) != 0 {
                guard socketAddressOffset + 2 <= messageOffset + messageLength else { break }
                let length = Int(buffer[socketAddressOffset])
                let family = Int32(buffer[socketAddressOffset + 1])
                let paddedLength = length > 0 ? (length + 3) & ~3 : 4
                guard socketAddressOffset + paddedLength <= messageOffset + messageLength else { break }

                if addressIndex == RTAX_DST, family == AF_INET,
                   length >= MemoryLayout<sockaddr_in>.size {
                    let socketAddress = buffer.withUnsafeBytes {
                        $0.loadUnaligned(fromByteOffset: socketAddressOffset, as: sockaddr_in.self)
                    }
                    destination = UInt32(bigEndian: socketAddress.sin_addr.s_addr)
                } else if addressIndex == RTAX_GATEWAY, family == AF_LINK, length >= 8 {
                    let nameLength = Int(buffer[socketAddressOffset + 5])
                    let addressLength = Int(buffer[socketAddressOffset + 6])
                    let addressStart = socketAddressOffset + 8 + nameLength
                    if addressLength == 6, addressStart + addressLength <= socketAddressOffset + length {
                        macAddress = buffer[addressStart..<(addressStart + addressLength)]
                            .map { String(format: "%02X", $0) }
                            .joined(separator: ":")
                    }
                }

                socketAddressOffset += paddedLength
            }

            if destination == target.rawValue, let macAddress {
                return macAddress
            }
            messageOffset += messageLength
        }
        return nil
    }

    nonisolated private static func icmpChecksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var index = 0
        while index + 1 < bytes.count {
            sum += UInt32(bytes[index]) << 8 | UInt32(bytes[index + 1])
            index += 2
        }
        if index < bytes.count { sum += UInt32(bytes[index]) << 8 }
        while sum > 0xFFFF { sum = (sum & 0xFFFF) + (sum >> 16) }
        return ~UInt16(sum)
    }

    nonisolated private static func resolveHostname(
        for address: String,
        interfaceName: String
    ) -> String? {
        var socketAddress = sockaddr_in()
        socketAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        socketAddress.sin_family = sa_family_t(AF_INET)
        guard address.withCString({ inet_pton(AF_INET, $0, &socketAddress.sin_addr) }) == 1 else {
            return nil
        }

        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let status = withUnsafePointer(to: &socketAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketPointer in
                getnameinfo(
                    socketPointer,
                    socklen_t(MemoryLayout<sockaddr_in>.size),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NAMEREQD
                )
            }
        }
        if status == 0,
           let resolved = normalizedHostname(decodedCString(hostname)),
           resolved != address {
            return resolved
        }
        return resolveMulticastDNSHostname(
            for: address,
            interfaceIndex: if_nametoindex(interfaceName)
        )
    }

    nonisolated private static func resolveMulticastDNSHostname(
        for address: String,
        interfaceIndex: UInt32
    ) -> String? {
        let labels = address.split(separator: ".").reversed()
        let reverseName = labels.joined(separator: ".") + ".in-addr.arpa."
        let resultBox = DNSHostnameResultBox()
        let context = Unmanaged.passUnretained(resultBox).toOpaque()
        var service: DNSServiceRef?
        let createStatus = DNSServiceQueryRecord(
            &service,
            DNSServiceFlags(kDNSServiceFlagsForceMulticast),
            interfaceIndex,
            reverseName,
            UInt16(kDNSServiceType_PTR),
            UInt16(kDNSServiceClass_IN),
            dnsHostnameQueryCallback,
            context
        )
        guard createStatus == kDNSServiceErr_NoError, let service else { return nil }
        defer { DNSServiceRefDeallocate(service) }

        var descriptor = pollfd(
            fd: DNSServiceRefSockFD(service),
            events: Int16(POLLIN),
            revents: 0
        )
        guard descriptor.fd >= 0,
              poll(&descriptor, 1, 500) > 0,
              (descriptor.revents & Int16(POLLIN)) != 0,
              DNSServiceProcessResult(service) == kDNSServiceErr_NoError
        else { return nil }
        return normalizedHostname(resultBox.hostname)
    }

    nonisolated private static func normalizedHostname(_ value: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        while value.hasSuffix(".") { value.removeLast() }
        return value.isEmpty ? nil : value
    }

    nonisolated private static func vendorName(for macAddress: String?) -> String? {
        guard let macAddress else { return nil }
        let vendor = OUIVendorLookup.shared.vendorName(for: macAddress)
        return vendor.hasPrefix("Unknown") ? nil : vendor
    }
}

struct ActiveNetworkScanResolver {
    nonisolated static func resolve() throws -> NetworkScanRequest {
        let dynamicStore = SCDynamicStoreCreate(nil, "MacSpeedMonitor.NetworkScanner" as CFString, nil, nil)
        let globalIPv4 = dynamicStore.flatMap {
            SCDynamicStoreCopyValue($0, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        }
        let primaryInterface = globalIPv4?["PrimaryInterface"] as? String
        let routerAddress = globalIPv4?["Router"] as? String

        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else {
            throw NetworkScanError.noActiveInterface
        }
        defer { freeifaddrs(pointer) }

        var localAddress: String?
        var netmask: String?
        var localMACAddress: String?
        var current: UnsafeMutablePointer<ifaddrs>? = first

        while let node = current {
            let interface = node.pointee
            let name = String(cString: interface.ifa_name)
            guard name == primaryInterface else {
                current = interface.ifa_next
                continue
            }

            if interface.ifa_addr?.pointee.sa_family == UInt8(AF_INET) {
                localAddress = stringAddress(interface.ifa_addr)
                netmask = stringAddress(interface.ifa_netmask)
            } else if interface.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
                      let linkAddress = interface.ifa_addr {
                localMACAddress = macAddress(linkAddress)
            }
            current = interface.ifa_next
        }

        guard let interfaceName = primaryInterface,
              !isVirtualInterface(interfaceName),
              let localAddress,
              let netmask
        else {
            throw NetworkScanError.noActiveInterface
        }

        return try NetworkScanRequest.make(
            interfaceName: interfaceName,
            address: localAddress,
            netmask: netmask,
            routerAddress: routerAddress,
            localMACAddress: localMACAddress
        )
    }

    nonisolated private static func stringAddress(_ pointer: UnsafeMutablePointer<sockaddr>?) -> String? {
        guard let pointer else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let status = getnameinfo(
            pointer,
            socklen_t(pointer.pointee.sa_len),
            &buffer,
            socklen_t(buffer.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        return status == 0 ? decodedCString(buffer) : nil
    }

    nonisolated private static func macAddress(_ pointer: UnsafeMutablePointer<sockaddr>) -> String? {
        let link = pointer.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { $0.pointee }
        guard link.sdl_alen == 6 else { return nil }
        return withUnsafeBytes(of: link.sdl_data) { dataBytes in
            let start = Int(link.sdl_nlen)
            guard dataBytes.count >= start + 6 else { return nil }
            return dataBytes[start..<(start + 6)]
                .map { String(format: "%02X", $0) }
                .joined(separator: ":")
        }
    }

    nonisolated private static func isVirtualInterface(_ name: String) -> Bool {
        let normalized = name.lowercased()
        return ["utun", "tun", "tap", "ppp", "ipsec", "wg", "tailscale", "zt", "vpn"]
            .contains { normalized.hasPrefix($0) }
    }
}

struct IPv4AddressValue: Sendable, Equatable, Comparable, CustomStringConvertible {
    let rawValue: UInt32

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    init?(_ string: String) {
        var address = in_addr()
        guard string.withCString({ inet_pton(AF_INET, $0, &address) }) == 1 else { return nil }
        rawValue = UInt32(bigEndian: address.s_addr)
    }

    var description: String {
        var address = in_addr(s_addr: rawValue.bigEndian)
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &address, &buffer, socklen_t(buffer.count)) != nil else { return "" }
        return decodedCString(buffer)
    }

    var isPrivate: Bool {
        let first = rawValue >> 24
        let second = (rawValue >> 16) & 0xFF
        return first == 10 || (first == 172 && (16...31).contains(second)) || (first == 192 && second == 168)
    }

    var contiguousPrefixLength: Int? {
        var encounteredZero = false
        var prefixLength = 0
        for bitIndex in (0..<32).reversed() {
            let isOne = (rawValue & (UInt32(1) << UInt32(bitIndex))) != 0
            if isOne {
                if encounteredZero { return nil }
                prefixLength += 1
            } else {
                encounteredZero = true
            }
        }
        return prefixLength
    }

    static func < (lhs: IPv4AddressValue, rhs: IPv4AddressValue) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct NetworkScanDeviceStore: Sendable {
    private var devicesByAddress: [String: DiscoveredNetworkDevice]

    init(devices: [DiscoveredNetworkDevice] = []) {
        devicesByAddress = Dictionary(uniqueKeysWithValues: devices.map { ($0.ipv4Address, $0) })
    }

    var sortedDevices: [DiscoveredNetworkDevice] {
        devicesByAddress.values.sorted(by: Self.areInDisplayOrder)
    }

    mutating func markAllStale() {
        for address in devicesByAddress.keys {
            devicesByAddress[address]?.isStale = true
        }
    }

    mutating func merge(_ update: DiscoveredNetworkDevice) {
        guard var current = devicesByAddress[update.ipv4Address] else {
            devicesByAddress[update.ipv4Address] = update
            return
        }
        current.hostname = update.hostname ?? current.hostname
        current.macAddress = update.macAddress ?? current.macAddress
        current.vendorName = update.vendorName ?? current.vendorName
        current.responseTimeMilliseconds = update.responseTimeMilliseconds ?? current.responseTimeMilliseconds
        current.isRouter = current.isRouter || update.isRouter
        current.isLocalDevice = current.isLocalDevice || update.isLocalDevice
        current.lastSeenAt = update.lastSeenAt
        current.isStale = false
        devicesByAddress[update.ipv4Address] = current
    }

    mutating func removeStaleDevices() {
        devicesByAddress = devicesByAddress.filter { !$0.value.isStale }
    }

    static func areInDisplayOrder(
        _ left: DiscoveredNetworkDevice,
        _ right: DiscoveredNetworkDevice
    ) -> Bool {
        if left.isRouter != right.isRouter { return left.isRouter }
        if left.isLocalDevice != right.isLocalDevice { return left.isLocalDevice }
        let leftValue = IPv4AddressValue(left.ipv4Address)?.rawValue ?? UInt32.max
        let rightValue = IPv4AddressValue(right.ipv4Address)?.rawValue ?? UInt32.max
        return leftValue < rightValue
    }
}

private struct ProbeResult: Sendable {
    let address: String
    let responseTimeMilliseconds: Double?
    let macAddress: String?
    var isReachable: Bool { responseTimeMilliseconds != nil }

    init(address: String, responseTimeMilliseconds: Double?, macAddress: String? = nil) {
        self.address = address
        self.responseTimeMilliseconds = responseTimeMilliseconds
        self.macAddress = macAddress
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private func decodedCString(_ bytes: [CChar]) -> String {
    let end = bytes.firstIndex(of: 0) ?? bytes.endIndex
    return String(decoding: bytes[..<end].map(UInt8.init(bitPattern:)), as: UTF8.self)
}

private final class DNSHostnameResultBox: @unchecked Sendable {
    var hostname: String?
}

private let dnsHostnameQueryCallback: DNSServiceQueryRecordReply = {
    _, _, _, errorCode, _, rrtype, _, dataLength, recordData, _, context in
    guard errorCode == kDNSServiceErr_NoError,
          rrtype == UInt16(kDNSServiceType_PTR),
          let recordData,
          let context
    else { return }

    let bytes = UnsafeRawBufferPointer(start: recordData, count: Int(dataLength))
    var labels: [String] = []
    var offset = 0
    while offset < bytes.count {
        let length = Int(bytes[offset])
        if length == 0 { break }
        guard length < 64, offset + 1 + length <= bytes.count else { return }
        let labelBytes = bytes[(offset + 1)..<(offset + 1 + length)]
        labels.append(String(decoding: labelBytes, as: UTF8.self))
        offset += length + 1
    }
    guard !labels.isEmpty else { return }
    let box = Unmanaged<DNSHostnameResultBox>.fromOpaque(context).takeUnretainedValue()
    box.hostname = labels.joined(separator: ".")
}
