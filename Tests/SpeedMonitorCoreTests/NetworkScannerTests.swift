import XCTest
@testable import SpeedMonitorCore

final class NetworkScannerTests: XCTestCase {
    func testLiveScannerRecognizesLocalNetworkDevicesWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["LIVE_NETWORK_SCAN"] == "1" else {
            throw XCTSkip("Set LIVE_NETWORK_SCAN=1 to exercise the production scanner on the current LAN.")
        }

        let request = try ActiveNetworkScanResolver.resolve()
        var devicesByAddress: [String: DiscoveredNetworkDevice] = [:]

        for try await event in LocalNetworkScanner().scan(request: request) {
            if case .device(let device) = event {
                devicesByAddress[device.ipv4Address] = device
            }
        }

        XCTAssertNotNil(devicesByAddress[request.localIPv4Address])
        if let routerAddress = request.routerIPv4Address {
            XCTAssertNotNil(devicesByAddress[routerAddress])
        }
        let responsiveCount = devicesByAddress.values.filter { $0.responseTimeMilliseconds != nil }.count
        let enrichedCount = devicesByAddress.values.filter { $0.hostname != nil || $0.macAddress != nil }.count
        print("Live scan recognized \(devicesByAddress.count) devices; \(responsiveCount) responded and \(enrichedCount) had hostname or MAC metadata.")
        XCTAssertTrue(
            responsiveCount > 0,
            "No device returned an ICMP response on the current LAN."
        )
    }

    func testSlash24RequestDerivesExpectedRange() throws {
        let request = try NetworkScanRequest.make(
            interfaceName: "en0",
            address: "192.168.10.42",
            netmask: "255.255.255.0",
            routerAddress: "192.168.10.1"
        )

        XCTAssertEqual(request.prefixLength, 24)
        XCTAssertEqual(request.networkAddress, "192.168.10.0")
        XCTAssertEqual(request.broadcastAddress, "192.168.10.255")
        XCTAssertEqual(request.candidateHostAddresses.count, 254)
        XCTAssertEqual(request.candidateHostAddresses.first, "192.168.10.1")
        XCTAssertEqual(request.candidateHostAddresses.last, "192.168.10.254")
        XCTAssertEqual(request.routerIPv4Address, "192.168.10.1")
    }

    func testSmallerSubnetDerivesOnlyUsableHosts() throws {
        let request = try NetworkScanRequest.make(
            interfaceName: "en0",
            address: "10.0.0.5",
            netmask: "255.255.255.252"
        )

        XCTAssertEqual(request.prefixLength, 30)
        XCTAssertEqual(request.candidateHostAddresses, ["10.0.0.5", "10.0.0.6"])
    }

    func testRejectsUnsupportedNetworks() {
        XCTAssertThrowsError(try NetworkScanRequest.make(
            interfaceName: "en0",
            address: "8.8.8.8",
            netmask: "255.255.255.0"
        )) { XCTAssertEqual($0 as? NetworkScanError, .noPrivateIPv4Network) }

        XCTAssertThrowsError(try NetworkScanRequest.make(
            interfaceName: "en0",
            address: "192.168.1.2",
            netmask: "255.255.0.0"
        )) { XCTAssertEqual($0 as? NetworkScanError, .oversizedSubnet) }

        XCTAssertThrowsError(try NetworkScanRequest.make(
            interfaceName: "en0",
            address: "192.168.1.2",
            netmask: "255.0.255.0"
        )) { XCTAssertEqual($0 as? NetworkScanError, .invalidSubnet) }

        XCTAssertThrowsError(try NetworkScanRequest.make(
            interfaceName: "en0",
            address: "192.168.1.2",
            netmask: "255.255.255.254"
        )) { XCTAssertEqual($0 as? NetworkScanError, .invalidSubnet) }
    }

    func testDeviceNormalizesMACAndRejectsInvalidAddresses() throws {
        let device = try XCTUnwrap(DiscoveredNetworkDevice(
            ipv4Address: "192.168.1.8",
            macAddress: "aa-bb-cc-dd-ee-ff"
        ))

        XCTAssertEqual(device.macAddress, "AA:BB:CC:DD:EE:FF")
        XCTAssertNil(DiscoveredNetworkDevice(ipv4Address: "not-an-address"))
    }

    func testStoreDeduplicatesEnrichesAndSortsNumerically() throws {
        let router = try XCTUnwrap(DiscoveredNetworkDevice(
            ipv4Address: "192.168.1.1",
            isRouter: true
        ))
        let local = try XCTUnwrap(DiscoveredNetworkDevice(
            ipv4Address: "192.168.1.20",
            isLocalDevice: true
        ))
        let high = try XCTUnwrap(DiscoveredNetworkDevice(ipv4Address: "192.168.1.100"))
        let low = try XCTUnwrap(DiscoveredNetworkDevice(ipv4Address: "192.168.1.9"))
        let enrichedLow = try XCTUnwrap(DiscoveredNetworkDevice(
            ipv4Address: "192.168.1.9",
            hostname: "printer.local",
            responseTimeMilliseconds: 4.5
        ))

        var store = NetworkScanDeviceStore(devices: [high, local, router, low])
        store.merge(enrichedLow)

        XCTAssertEqual(store.sortedDevices.map(\.ipv4Address), [
            "192.168.1.1", "192.168.1.20", "192.168.1.9", "192.168.1.100",
        ])
        XCTAssertEqual(store.sortedDevices.count, 4)
        XCTAssertEqual(store.sortedDevices[2].hostname, "printer.local")
        XCTAssertEqual(store.sortedDevices[2].responseTimeMilliseconds, 4.5)
    }

    func testStoreMarksAndRemovesOnlyStaleDevices() throws {
        let first = try XCTUnwrap(DiscoveredNetworkDevice(ipv4Address: "10.0.0.1"))
        let second = try XCTUnwrap(DiscoveredNetworkDevice(ipv4Address: "10.0.0.2"))
        var store = NetworkScanDeviceStore(devices: [first, second])

        store.markAllStale()
        store.merge(first)
        store.removeStaleDevices()

        XCTAssertEqual(store.sortedDevices.map(\.ipv4Address), ["10.0.0.1"])
        XCTAssertFalse(store.sortedDevices[0].isStale)
    }
}
