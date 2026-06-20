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
