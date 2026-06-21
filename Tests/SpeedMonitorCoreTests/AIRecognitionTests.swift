import XCTest
@testable import SpeedMonitorCore

final class AIRecognitionTests: XCTestCase {
    override func tearDown() {
        TestURLProtocol.handler = nil
        super.tearDown()
    }

    func testRecognitionRequestIsRedactedAndStructuredResponseDecodes() async throws {
        let keyStore = MemoryAPIKeyStore(key: "test-key")
        let session = makeSession()
        let provider = OpenAIRecognitionProvider(session: session, keyStore: keyStore)
        let device = try XCTUnwrap(DiscoveredNetworkDevice(
            ipv4Address: "192.168.50.44",
            hostname: "living-room-speaker.local",
            macAddress: "AA:BB:CC:DD:EE:FF",
            vendorName: "Example Vendor",
            responseTimeMilliseconds: 3.27
        ))

        TestURLProtocol.handler = { request in
            XCTAssertEqual(request.url, OpenAIRecognitionProvider.responsesURL)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            let body = try XCTUnwrap(Self.bodyData(from: request))
            let text = String(decoding: body, as: UTF8.self)
            XCTAssertFalse(text.contains("192.168.50.44"))
            XCTAssertFalse(text.contains("AA:BB:CC:DD:EE:FF"))
            XCTAssertTrue(text.contains("living-room-speaker.local"))
            XCTAssertTrue(text.contains("Example Vendor"))
            XCTAssertTrue(text.contains("\"store\":false"))
            XCTAssertTrue(text.contains("json_schema"))
            return Self.response(
                status: 200,
                body: """
                {"output":[{"content":[{"type":"output_text","text":"{\\"recognitions\\":[{\\"itemID\\":\\"item-1\\",\\"suggestedName\\":\\"Likely smart-home device\\",\\"category\\":\\"IoT\\",\\"likelyPurpose\\":\\"Home automation\\",\\"confidence\\":\\"medium\\",\\"rationale\\":\\"Vendor evidence\\",\\"limitations\\":\\"Exact model is unknown\\"}]}"}]}]}
                """
            )
        }

        let result = try await provider.recognize([
            AIRecognitionInput(itemID: "item-1", device: device),
        ])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].confidence, .medium)
        XCTAssertEqual(result[0].category, "IoT")
    }

    func testGeminiRequestIsRedactedUsesSharedPromptAndDecodesStructuredResponse() async throws {
        let provider = GeminiRecognitionProvider(
            session: makeSession(),
            keyStore: MemoryAPIKeyStore(key: "gemini-test-key")
        )
        let device = try XCTUnwrap(DiscoveredNetworkDevice(
            ipv4Address: "192.168.50.44",
            hostname: "living-room-speaker.local",
            macAddress: "AA:BB:CC:DD:EE:FF",
            vendorName: "Example Vendor",
            responseTimeMilliseconds: 3.27
        ))

        TestURLProtocol.handler = { request in
            XCTAssertEqual(request.url, GeminiRecognitionProvider.generateContentURL)
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "gemini-test-key")
            let body = try XCTUnwrap(Self.bodyData(from: request))
            let text = String(decoding: body, as: UTF8.self)
            XCTAssertFalse(text.contains("192.168.50.44"))
            XCTAssertFalse(text.contains("AA:BB:CC:DD:EE:FF"))
            XCTAssertTrue(text.contains("living-room-speaker.local"))
            XCTAssertTrue(text.contains("Example Vendor"))
            XCTAssertTrue(text.contains("Classify local network devices"))
            XCTAssertTrue(text.contains("responseSchema"))
            return Self.geminiResponse(
                status: 200,
                body: """
                {"candidates":[{"content":{"parts":[{"text":"{\\"recognitions\\":[{\\"itemID\\":\\"item-1\\",\\"suggestedName\\":\\"Likely smart speaker\\",\\"category\\":\\"Audio\\",\\"likelyPurpose\\":\\"Playing media\\",\\"confidence\\":\\"medium\\",\\"rationale\\":\\"Hostname evidence\\",\\"limitations\\":\\"Exact model unknown\\"}]}"}]},"finishReason":"STOP"}]}
                """
            )
        }

        let result = try await provider.recognize([
            AIRecognitionInput(itemID: "item-1", device: device),
        ])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].category, "Audio")
        XCTAssertEqual(result[0].method, .googleGemini)
    }

    func testHTTPFailuresMapToActionableErrors() async throws {
        let provider = OpenAIRecognitionProvider(
            session: makeSession(),
            keyStore: MemoryAPIKeyStore(key: "test-key")
        )
        let device = try XCTUnwrap(DiscoveredNetworkDevice(ipv4Address: "10.0.0.2"))
        let input = AIRecognitionInput(itemID: "item-1", device: device)

        for (status, expected) in [
            (401, AIRecognitionError.invalidAPIKey),
            (404, AIRecognitionError.modelUnavailable),
            (429, AIRecognitionError.rateLimited),
        ] {
            TestURLProtocol.handler = { _ in Self.response(status: status, body: "{}") }
            do {
                _ = try await provider.recognize([input])
                XCTFail("Expected status \(status) to fail")
            } catch let error as AIRecognitionError {
                XCTAssertEqual(error, expected)
            }
        }
    }

    func testMalformedAndRefusedResponsesAreRejected() async throws {
        let provider = OpenAIRecognitionProvider(
            session: makeSession(),
            keyStore: MemoryAPIKeyStore(key: "test-key")
        )
        let device = try XCTUnwrap(DiscoveredNetworkDevice(ipv4Address: "10.0.0.2"))
        let input = AIRecognitionInput(itemID: "item-1", device: device)

        TestURLProtocol.handler = { _ in Self.response(status: 200, body: "{\"output\":[]}") }
        do {
            _ = try await provider.recognize([input])
            XCTFail("Expected malformed response failure")
        } catch let error as AIRecognitionError {
            XCTAssertEqual(error, .invalidResponse)
        }

        TestURLProtocol.handler = { _ in
            Self.response(
                status: 200,
                body: "{\"output\":[{\"content\":[{\"type\":\"refusal\",\"refusal\":\"Unable to help\"}]}]}"
            )
        }
        do {
            _ = try await provider.recognize([input])
            XCTFail("Expected refusal")
        } catch let error as AIRecognitionError {
            XCTAssertEqual(error, .refused("Unable to help"))
        }
    }

    func testBatcherUsesMaximumOfTwentyFiveItems() {
        let batches = AIRecognitionBatcher.batches(from: Array(0..<61))
        XCTAssertEqual(batches.map(\.count), [25, 25, 11])
        XCTAssertEqual(batches.flatMap { $0 }, Array(0..<61))
    }

    func testMethodSelectionPrefersAvailableAppleUntilUserMakesAChoice() {
        XCTAssertEqual(
            AIRecognitionMethodSelection.initialMethod(
                storedRawValue: nil,
                appleAvailability: .available
            ),
            .appleOnDevice
        )
        XCTAssertEqual(
            AIRecognitionMethodSelection.initialMethod(
                storedRawValue: nil,
                appleAvailability: .unavailable("Not ready")
            ),
            .openAI
        )
        XCTAssertEqual(
            AIRecognitionMethodSelection.initialMethod(
                storedRawValue: AIRecognitionMethod.openAI.rawValue,
                appleAvailability: .available
            ),
            .openAI
        )
    }

    func testProvidersDeclareMethodSpecificBatchSizes() {
        XCTAssertEqual(
            OpenAIRecognitionProvider(keyStore: MemoryAPIKeyStore(key: "test-key")).maximumBatchSize,
            25
        )
        XCTAssertEqual(
            UnavailableAIRecognitionProvider(method: .appleOnDevice, reason: "Unavailable").maximumBatchSize,
            1
        )
        XCTAssertEqual(
            GeminiRecognitionProvider(keyStore: MemoryAPIKeyStore(key: "test-key")).maximumBatchSize,
            25
        )
    }

    func testLegacyRecognitionWithoutMethodDecodesAsOpenAI() throws {
        let data = Data("""
            {
              "itemID": "item-1",
              "suggestedName": "Smart speaker",
              "category": "Audio",
              "likelyPurpose": "Playing music",
              "confidence": "medium",
              "rationale": "Vendor evidence",
              "limitations": "Exact model unknown"
            }
            """.utf8)

        let recognition = try JSONDecoder().decode(DeviceAIRecognition.self, from: data)
        XCTAssertEqual(recognition.method, .openAI)
    }

    func testRecognizedNameReplacesOnlyUnknownDeviceFallback() throws {
        let recognition = DeviceAIRecognition(
            itemID: "item-1",
            suggestedName: "  Smart speaker  ",
            category: "Audio",
            likelyPurpose: "Playing media",
            confidence: .medium,
            rationale: "Vendor evidence",
            limitations: "Exact model unknown"
        )
        let state = DeviceAIRecognitionState.recognized(recognition)
        let unknownDevice = try XCTUnwrap(DiscoveredNetworkDevice(ipv4Address: "192.168.1.20"))
        let namedDevice = try XCTUnwrap(DiscoveredNetworkDevice(
            ipv4Address: "192.168.1.21",
            hostname: "printer.local"
        ))
        let router = try XCTUnwrap(DiscoveredNetworkDevice(
            ipv4Address: "192.168.1.1",
            isRouter: true
        ))

        XCTAssertEqual(unknownDevice.displayName(aiState: state), "Smart speaker")
        XCTAssertEqual(namedDevice.displayName(aiState: state), "printer.local")
        XCTAssertEqual(router.displayName(aiState: state), "Router")
        XCTAssertEqual(unknownDevice.displayName(aiState: .analyzing), "Unknown Device")

        let blankRecognition = DeviceAIRecognition(
            itemID: "item-1",
            suggestedName: " \n ",
            category: "Unknown",
            likelyPurpose: "Unknown",
            confidence: .low,
            rationale: "Insufficient evidence",
            limitations: "Unable to recognize"
        )
        XCTAssertEqual(
            unknownDevice.displayName(aiState: .recognized(blankRecognition)),
            "Unknown Device"
        )
    }

    func testRecognizedDeviceTypeChangesUnknownDeviceIcon() throws {
        let unknownDevice = try XCTUnwrap(DiscoveredNetworkDevice(ipv4Address: "192.168.1.20"))
        let recognition = DeviceAIRecognition(
            itemID: "item-1",
            suggestedName: "Living Room Speaker",
            category: "Smart home audio",
            likelyPurpose: "Playing music",
            confidence: .high,
            rationale: "Hostname and vendor evidence",
            limitations: "Exact model unknown"
        )

        XCTAssertEqual(unknownDevice.systemImageName(aiState: nil), "network")
        XCTAssertEqual(
            unknownDevice.systemImageName(aiState: .recognized(recognition)),
            "hifispeaker.fill"
        )
    }

    func testDeviceIconKeepsKnownRolesAndFallsBackForUnrecognizedCategories() throws {
        let router = try XCTUnwrap(DiscoveredNetworkDevice(
            ipv4Address: "192.168.1.1",
            isRouter: true
        ))
        let localDevice = try XCTUnwrap(DiscoveredNetworkDevice(
            ipv4Address: "192.168.1.2",
            isLocalDevice: true
        ))
        let unknownDevice = try XCTUnwrap(DiscoveredNetworkDevice(ipv4Address: "192.168.1.3"))
        let recognition = DeviceAIRecognition(
            itemID: "item-1",
            suggestedName: "Specialized device",
            category: "Unclassified",
            likelyPurpose: "Unknown",
            confidence: .low,
            rationale: "Limited evidence",
            limitations: "Unable to determine a type"
        )

        XCTAssertEqual(router.systemImageName(aiState: .recognized(recognition)), "wifi.router.fill")
        XCTAssertEqual(localDevice.systemImageName(aiState: .recognized(recognition)), "desktopcomputer")
        XCTAssertEqual(unknownDevice.systemImageName(aiState: .recognized(recognition)), "network")
    }

    func testKeychainStoreSavesReplacesAndRemovesKey() throws {
        let store = OpenAIAPIKeyStore(
            service: "com.adisapir.MacSpeedMonitor.tests.\(UUID().uuidString)",
            account: "test"
        )
        defer { try? store.removeKey() }

        XCTAssertFalse(store.hasKey)
        try store.saveKey("first-key")
        XCTAssertEqual(try store.loadKey(), "first-key")
        try store.saveKey("replacement-key")
        XCTAssertEqual(try store.loadKey(), "replacement-key")
        try store.removeKey()
        XCTAssertNil(try store.loadKey())
    }

    func testDeviceHistoryRoundTripsAndEnrichesByMACAddress() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacSpeedMonitor-history-\(UUID().uuidString)")
        let fileURL = directory.appendingPathComponent("device-history.json")
        let store = LocalDeviceHistoryStore(fileURL: fileURL)
        defer { try? FileManager.default.removeItem(at: directory) }

        let originalDevice = try XCTUnwrap(DiscoveredNetworkDevice(
            ipv4Address: "192.168.1.20",
            hostname: "living-room-device.local",
            macAddress: "AA:BB:CC:DD:EE:FF",
            vendorName: "Example Vendor",
            responseTimeMilliseconds: 4.2
        ))
        let recognition = DeviceAIRecognition(
            itemID: "item-1",
            suggestedName: "Likely media player",
            category: "Entertainment",
            likelyPurpose: "Streaming media",
            confidence: .medium,
            rationale: "Vendor evidence",
            limitations: "Exact model unknown"
        )
        let record = try XCTUnwrap(PersistedDeviceRecord(
            device: originalDevice,
            aiRecognition: recognition
        ))

        try store.save([record.macAddress: record])
        let loaded = try store.load()
        let loadedRecord = try XCTUnwrap(loaded[record.macAddress])
        XCTAssertEqual(loadedRecord.macAddress, record.macAddress)
        XCTAssertEqual(loadedRecord.hostname, record.hostname)
        XCTAssertEqual(loadedRecord.vendorName, record.vendorName)
        XCTAssertEqual(loadedRecord.aiRecognition, record.aiRecognition)
        XCTAssertEqual(
            loadedRecord.lastSeenAt.timeIntervalSince(record.lastSeenAt),
            0,
            accuracy: 1
        )

        let rediscovered = try XCTUnwrap(DiscoveredNetworkDevice(
            ipv4Address: "192.168.1.87",
            macAddress: "AA:BB:CC:DD:EE:FF"
        ))
        let enriched = try XCTUnwrap(loaded[record.macAddress]?.enriching(rediscovered))
        XCTAssertEqual(enriched.ipv4Address, "192.168.1.87")
        XCTAssertEqual(enriched.hostname, "living-room-device.local")
        XCTAssertEqual(enriched.vendorName, "Example Vendor")
        XCTAssertEqual(loaded[record.macAddress]?.aiRecognition, recognition)

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(permissions.map { $0 & 0o777 }, 0o600)

        try store.remove()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testDeviceWithoutMACCannotBecomePersistentRecord() throws {
        let device = try XCTUnwrap(DiscoveredNetworkDevice(ipv4Address: "10.0.0.8"))
        XCTAssertNil(PersistedDeviceRecord(device: device, aiRecognition: nil))
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(status: Int, body: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: OpenAIRecognitionProvider.responsesURL,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(body.utf8))
    }

    private static func geminiResponse(status: Int, body: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: GeminiRecognitionProvider.generateContentURL,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(body.utf8))
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            result.append(buffer, count: count)
        }
        return result
    }
}

private final class MemoryAPIKeyStore: APIKeyStoring, @unchecked Sendable {
    private var key: String?
    init(key: String?) { self.key = key }
    var hasKey: Bool { key?.isEmpty == false }
    func loadKey() throws -> String? { key }
    func saveKey(_ key: String) throws { self.key = key }
    func removeKey() throws { key = nil }
}

private final class TestURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let handler = try XCTUnwrap(Self.handler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
