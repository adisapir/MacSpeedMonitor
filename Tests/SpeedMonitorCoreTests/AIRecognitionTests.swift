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
            XCTAssertTrue(text.contains("\\\"openPorts\\\""))
            XCTAssertTrue(text.contains("\\\"port\\\":22"))
            XCTAssertTrue(text.contains("SSH"))
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
            AIRecognitionInput(
                itemID: "item-1",
                device: device,
                enhancedScan: DeviceEnhancedScanResult(
                    openPorts: [OpenPort(port: 22, serviceName: "SSH")],
                    pingTTL: 64,
                    httpServerHeaders: [HTTPServerHeader(port: 80, value: "nginx")]
                )
            ),
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
            XCTAssertFalse(text.contains("additionalProperties"))
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

    func testRecognitionInputIncludesCompletedEnhancedScanResultsWhenProvided() throws {
        let device = try XCTUnwrap(DiscoveredNetworkDevice(
            ipv4Address: "192.168.50.44",
            hostname: "living-room-speaker.local",
            macAddress: "AA:BB:CC:DD:EE:FF",
            vendorName: "Example Vendor",
            responseTimeMilliseconds: 3.27,
            pingTTL: 64
        ))

        let input = AIRecognitionInput(
            itemID: "item-1",
            device: device,
            enhancedScan: DeviceEnhancedScanResult(
                openPorts: [
                    OpenPort(port: 22, serviceName: "SSH"),
                    OpenPort(port: 8080, serviceName: "HTTP Alt"),
                ],
                pingTTL: 64,
                httpServerHeaders: [HTTPServerHeader(port: 8080, value: "Apache")]
            )
        )
        let data = try JSONEncoder().encode(input)
        let text = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(text.contains("192.168.50.44"))
        XCTAssertFalse(text.contains("AA:BB:CC:DD:EE:FF"))
        XCTAssertTrue(text.contains("\"openPorts\""))
        XCTAssertTrue(text.contains("\"port\":22"))
        XCTAssertTrue(text.contains("\"serviceName\":\"SSH\""))
        XCTAssertTrue(text.contains("\"port\":8080"))
        XCTAssertTrue(text.contains("\"serviceName\":\"HTTP Alt\""))
        XCTAssertTrue(text.contains("\"pingTTL\":64"))
        XCTAssertTrue(text.contains("\"httpServerHeaders\""))
        XCTAssertTrue(text.contains("\"value\":\"Apache\""))
    }

    func testDebugPromptsShowAgentAndPreserveRedactedDeviceMetadata() throws {
        let device = try XCTUnwrap(DiscoveredNetworkDevice(
            ipv4Address: "192.168.50.44",
            hostname: "living-room-speaker.local",
            macAddress: "AA:BB:CC:DD:EE:FF",
            vendorName: "Example Vendor",
            responseTimeMilliseconds: 3.27
        ))
        let input = AIRecognitionInput(itemID: "item-1", device: device)

        let openAIPrompt = try OpenAIRecognitionProvider(
            keyStore: MemoryAPIKeyStore(key: "test-key")
        )
        .debugPrompt(for: [input])
        XCTAssertEqual(openAIPrompt.agentDescription, "OpenAI API (\(OpenAIRecognitionProvider.model))")
        XCTAssertTrue(openAIPrompt.prompt.contains("developer:"))
        XCTAssertTrue(openAIPrompt.prompt.contains("user:"))
        XCTAssertTrue(openAIPrompt.prompt.contains("living-room-speaker.local"))
        XCTAssertTrue(openAIPrompt.prompt.contains("Example Vendor"))
        XCTAssertFalse(openAIPrompt.prompt.contains("192.168.50.44"))
        XCTAssertFalse(openAIPrompt.prompt.contains("AA:BB:CC:DD:EE:FF"))
        let openAILogMessage = openAIPrompt.logMessage(deviceCount: 1)
        XCTAssertTrue(openAILogMessage.contains("AI SCAN REQUEST BEGIN"))
        XCTAssertTrue(openAILogMessage.contains("Provider: OpenAI API"))
        XCTAssertTrue(openAILogMessage.contains("Prompt/Data:"))
        XCTAssertTrue(openAILogMessage.contains("AI SCAN REQUEST END"))

        let geminiPrompt = try GeminiRecognitionProvider(
            keyStore: MemoryAPIKeyStore(key: "gemini-test-key")
        )
        .debugPrompt(for: [input])
        XCTAssertEqual(geminiPrompt.agentDescription, "Google Gemini (\(GeminiRecognitionProvider.model))")
        XCTAssertTrue(geminiPrompt.prompt.contains("systemInstruction:"))
        XCTAssertTrue(geminiPrompt.prompt.contains("user:"))
        XCTAssertFalse(geminiPrompt.prompt.contains("192.168.50.44"))
        XCTAssertFalse(geminiPrompt.prompt.contains("AA:BB:CC:DD:EE:FF"))
    }

    func testGeminiMalformedRequestPreservesProviderErrorInsteadOfReportingInvalidKey() async throws {
        let provider = GeminiRecognitionProvider(
            session: makeSession(),
            keyStore: MemoryAPIKeyStore(key: "valid-key")
        )
        let device = try XCTUnwrap(DiscoveredNetworkDevice(ipv4Address: "10.0.0.2"))

        TestURLProtocol.handler = { _ in
            Self.geminiResponse(
                status: 400,
                body: """
                {"error":{"code":400,"message":"Malformed response schema","status":"INVALID_ARGUMENT"}}
                """
            )
        }

        do {
            _ = try await provider.recognize([
                AIRecognitionInput(itemID: "item-1", device: device),
            ])
            XCTFail("Expected malformed request to fail")
        } catch let error as AIRecognitionError {
            XCTAssertEqual(error, .server("Malformed response schema"))
        }
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
        let localDevice = try XCTUnwrap(DiscoveredNetworkDevice(
            ipv4Address: "192.168.1.2",
            hostname: "My-Device",
            isLocalDevice: true
        ))

        XCTAssertEqual(unknownDevice.displayName(aiState: state), "Smart speaker")
        XCTAssertEqual(namedDevice.displayName(aiState: state), "printer.local")
        XCTAssertEqual(router.displayName(aiState: state), "Router")
        XCTAssertEqual(localDevice.displayName(aiState: state), "My-Device (Smart Speaker)")
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
        let namedDevice = try XCTUnwrap(DiscoveredNetworkDevice(
            ipv4Address: "192.168.1.21",
            hostname: "living-room-speaker.local"
        ))
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
        XCTAssertEqual(
            namedDevice.systemImageName(aiState: .recognized(recognition)),
            "hifispeaker.fill"
        )
        XCTAssertEqual(
            recognition.withResolvedSystemImageName().systemImageName,
            "hifispeaker.fill"
        )
    }

    func testDeviceIconRequiresMediumOrHighConfidenceAndKnownCategory() throws {
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
            suggestedName: "Likely camera",
            category: "Camera",
            likelyPurpose: "Unknown",
            confidence: .low,
            rationale: "Limited evidence",
            limitations: "Unable to determine a type"
        )

        XCTAssertEqual(router.systemImageName(aiState: .recognized(recognition)), "wifi.router.fill")
        XCTAssertEqual(localDevice.systemImageName(aiState: .recognized(recognition)), "desktopcomputer")
        XCTAssertEqual(unknownDevice.systemImageName(aiState: .recognized(recognition)), "network")
        XCTAssertNil(recognition.withResolvedSystemImageName().systemImageName)

        let unrecognizedCategory = DeviceAIRecognition(
            itemID: "item-1",
            suggestedName: "Specialized device",
            category: "Unclassified",
            likelyPurpose: "Unknown",
            confidence: .medium,
            rationale: "Limited evidence",
            limitations: "Unable to determine a type"
        )
        XCTAssertEqual(unknownDevice.systemImageName(aiState: .recognized(unrecognizedCategory)), "network")
        XCTAssertNil(unrecognizedCategory.withResolvedSystemImageName().systemImageName)
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

    func testKeychainStoreCachesLoadedKeyToAvoidRepeatedAccess() throws {
        let service = "com.adisapir.MacSpeedMonitor.tests.\(UUID().uuidString)"
        let store = OpenAIAPIKeyStore(service: service, account: "test")
        let sideChannel = OpenAIAPIKeyStore(service: service, account: "test")
        defer { try? store.removeKey() }

        try store.saveKey("cached-key")
        XCTAssertEqual(try store.loadKey(), "cached-key")

        // Remove the item through a separate instance so `store`'s in-memory
        // cache is left intact.
        try sideChannel.removeKey()

        // `store` keeps serving the cached value without touching the keychain
        // again, while a brand-new instance sees the real (now empty) keychain.
        XCTAssertEqual(try store.loadKey(), "cached-key")
        XCTAssertTrue(store.hasKey)
        XCTAssertNil(try OpenAIAPIKeyStore(service: service, account: "test").loadKey())
    }

    func testExternalProviderAvailabilityDoesNotReadAPIKeys() {
        let openAIStore = CountingAPIKeyStore(key: "openai-key")
        let geminiStore = CountingAPIKeyStore(key: "gemini-key")

        XCTAssertTrue(OpenAIRecognitionProvider(keyStore: openAIStore).availability.isAvailable)
        XCTAssertTrue(GeminiRecognitionProvider(keyStore: geminiStore).availability.isAvailable)
        XCTAssertEqual(openAIStore.readCount, 0)
        XCTAssertEqual(geminiStore.readCount, 0)
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
        let resolvedRecognition = recognition.withResolvedSystemImageName()
        let record = try XCTUnwrap(PersistedDeviceRecord(
            device: originalDevice,
            aiRecognition: resolvedRecognition
        ))

        try store.save([record.primaryKey: record])
        let loaded = try store.load()
        let loadedRecord = try XCTUnwrap(loaded[record.primaryKey])
        XCTAssertEqual(loadedRecord.primaryKey, "mac:AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(loadedRecord.macAddress, record.macAddress)
        XCTAssertEqual(loadedRecord.hostname, record.hostname)
        XCTAssertEqual(loadedRecord.vendorName, record.vendorName)
        XCTAssertEqual(loadedRecord.aiRecognition, record.aiRecognition)
        XCTAssertEqual(loadedRecord.aiRecognition?.systemImageName, "tv.fill")
        XCTAssertEqual(
            loadedRecord.lastSeenAt.timeIntervalSince(record.lastSeenAt),
            0,
            accuracy: 1
        )

        let rediscovered = try XCTUnwrap(DiscoveredNetworkDevice(
            ipv4Address: "192.168.1.87",
            macAddress: "AA:BB:CC:DD:EE:FF"
        ))
        let enriched = try XCTUnwrap(loaded[record.primaryKey]?.enriching(rediscovered))
        XCTAssertEqual(enriched.ipv4Address, "192.168.1.87")
        XCTAssertEqual(enriched.hostname, "living-room-device.local")
        XCTAssertEqual(enriched.vendorName, "Example Vendor")
        XCTAssertEqual(loaded[record.primaryKey]?.aiRecognition, resolvedRecognition)

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(permissions.map { $0 & 0o777 }, 0o600)

        try store.remove()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testLoadCreatesEmptyHistoryFileWhenMissing() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacSpeedMonitor-history-\(UUID().uuidString)")
        let fileURL = directory.appendingPathComponent("device-history.json")
        let store = LocalDeviceHistoryStore(fileURL: fileURL)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))

        let records = try store.load()
        XCTAssertTrue(records.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        // The created file is valid and reloads as an empty history.
        XCTAssertTrue(try store.load().isEmpty)

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(permissions.map { $0 & 0o777 }, 0o600)
    }

    @MainActor
    func testCompletedScanPersistsDiscoveredDeviceToHistoryFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacSpeedMonitor-history-\(UUID().uuidString)")
        let fileURL = directory.appendingPathComponent("device-history.json")
        let store = LocalDeviceHistoryStore(fileURL: fileURL)
        defer { try? FileManager.default.removeItem(at: directory) }

        let defaults = try XCTUnwrap(UserDefaults(suiteName: "MacSpeedMonitorTests-\(UUID().uuidString)"))
        let monitor = NetworkSpeedMonitor(
            samplingInterval: 1,
            aiRecognitionProvider: UnavailableAIRecognitionProvider(method: .openAI, reason: "test"),
            deviceHistoryStore: store,
            aiRecognitionPreferences: defaults
        )

        let device = try XCTUnwrap(DiscoveredNetworkDevice(
            ipv4Address: "192.168.1.40",
            macAddress: "AA:BB:CC:DD:EE:99"
        ))
        monitor.handleNetworkScanEvent(.started(totalTargets: 1))
        monitor.handleNetworkScanEvent(.device(device))
        monitor.handleNetworkScanEvent(.completed(Date()))

        let reloaded = try store.load()
        XCTAssertNotNil(reloaded["mac:AA:BB:CC:DD:EE:99"], "completed scan should persist discovered device")
    }

    func testDeviceWithoutStableIdentifierCannotBecomePersistentRecord() throws {
        let device = try XCTUnwrap(DiscoveredNetworkDevice(ipv4Address: "10.0.0.8"))
        XCTAssertNil(PersistedDeviceRecord(device: device, aiRecognition: nil))
    }

    @MainActor
    func testRecognizedDeviceIsNoLongerTreatedAsUnknownOnLaterScan() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacSpeedMonitor-history-\(UUID().uuidString)")
        let fileURL = directory.appendingPathComponent("device-history.json")
        let store = LocalDeviceHistoryStore(fileURL: fileURL)
        defer { try? FileManager.default.removeItem(at: directory) }

        // A device with no hostname is intrinsically "unknown", but it was
        // recognized on an earlier scan and that result was persisted by MAC.
        let recognizedDevice = try XCTUnwrap(DiscoveredNetworkDevice(
            ipv4Address: "192.168.1.50",
            macAddress: "AA:BB:CC:DD:EE:01"
        ))
        XCTAssertTrue(recognizedDevice.isUnknownForAIRecognition)
        let recognition = DeviceAIRecognition(
            itemID: "item-1",
            suggestedName: "Smart speaker",
            category: "Smart Home",
            likelyPurpose: "Voice assistant",
            confidence: .high,
            rationale: "Vendor and open ports",
            limitations: "Exact model unknown"
        ).withResolvedSystemImageName()
        let record = try XCTUnwrap(PersistedDeviceRecord(
            device: recognizedDevice,
            aiRecognition: recognition
        ))
        try store.save([record.primaryKey: record])

        let defaults = try XCTUnwrap(UserDefaults(suiteName: "MacSpeedMonitorTests-\(UUID().uuidString)"))
        let monitor = NetworkSpeedMonitor(
            samplingInterval: 1,
            aiRecognitionProvider: UnavailableAIRecognitionProvider(method: .openAI, reason: "test"),
            deviceHistoryStore: store,
            aiRecognitionPreferences: defaults
        )

        // Rediscover the same device (new IP, still no hostname) on a later scan.
        let rediscovered = try XCTUnwrap(DiscoveredNetworkDevice(
            ipv4Address: "192.168.1.77",
            macAddress: "AA:BB:CC:DD:EE:01"
        ))
        monitor.mergeNetworkScanDevice(rediscovered)

        let merged = try XCTUnwrap(monitor.networkScanDevices.first)
        // It is still hostname-less in isolation...
        XCTAssertTrue(merged.isUnknownForAIRecognition)
        // ...but it must not be queued for the unknown-only AI pass anymore.
        XCTAssertTrue(monitor.unknownDevicesForAIRecognition.isEmpty)
        // ...and the persisted recognition name is shown instead of "Unknown Device".
        let aiState = monitor.aiRecognitionStates[merged.aiIdentity]
        XCTAssertEqual(merged.displayName(aiState: aiState), "Smart speaker")
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

private final class CountingAPIKeyStore: APIKeyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var key: String?
    private var reads = 0

    init(key: String?) { self.key = key }

    var readCount: Int {
        lock.withLock { reads }
    }

    var hasKey: Bool {
        lock.withLock {
            reads += 1
            return key?.isEmpty == false
        }
    }

    func loadKey() throws -> String? {
        lock.withLock {
            reads += 1
            return key
        }
    }

    func saveKey(_ key: String) throws {
        lock.withLock { self.key = key }
    }

    func removeKey() throws {
        lock.withLock { key = nil }
    }
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
