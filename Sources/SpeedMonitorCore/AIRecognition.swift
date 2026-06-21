import Foundation
import Security

public enum AIRecognitionMethod: String, Codable, Sendable, CaseIterable, Identifiable {
    case appleOnDevice
    case openAI

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .appleOnDevice: return "Apple On-Device"
        case .openAI: return "OpenAI API"
        }
    }
}

public enum AIRecognitionAvailability: Sendable, Equatable {
    case available
    case unavailable(String)

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    public var message: String {
        switch self {
        case .available: return "Ready"
        case .unavailable(let reason): return reason
        }
    }
}

struct AIRecognitionMethodSelection {
    static func initialMethod(
        storedRawValue: String?,
        appleAvailability: AIRecognitionAvailability
    ) -> AIRecognitionMethod {
        if let storedRawValue, let stored = AIRecognitionMethod(rawValue: storedRawValue) {
            return stored
        }
        return appleAvailability.isAvailable ? .appleOnDevice : .openAI
    }
}

public enum AIRecognitionConfidence: String, Codable, Sendable, CaseIterable {
    case low
    case medium
    case high
}

public struct DeviceAIRecognition: Codable, Sendable, Hashable {
    public let itemID: String
    public let suggestedName: String
    public let category: String
    public let likelyPurpose: String
    public let confidence: AIRecognitionConfidence
    public let rationale: String
    public let limitations: String
    public let method: AIRecognitionMethod

    public init(
        itemID: String,
        suggestedName: String,
        category: String,
        likelyPurpose: String,
        confidence: AIRecognitionConfidence,
        rationale: String,
        limitations: String,
        method: AIRecognitionMethod = .openAI
    ) {
        self.itemID = itemID
        self.suggestedName = suggestedName
        self.category = category
        self.likelyPurpose = likelyPurpose
        self.confidence = confidence
        self.rationale = rationale
        self.limitations = limitations
        self.method = method
    }

    private enum CodingKeys: String, CodingKey {
        case itemID, suggestedName, category, likelyPurpose, confidence, rationale, limitations, method
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        itemID = try container.decode(String.self, forKey: .itemID)
        suggestedName = try container.decode(String.self, forKey: .suggestedName)
        category = try container.decode(String.self, forKey: .category)
        likelyPurpose = try container.decode(String.self, forKey: .likelyPurpose)
        confidence = try container.decode(AIRecognitionConfidence.self, forKey: .confidence)
        rationale = try container.decode(String.self, forKey: .rationale)
        limitations = try container.decode(String.self, forKey: .limitations)
        method = try container.decodeIfPresent(AIRecognitionMethod.self, forKey: .method) ?? .openAI
    }
}

public enum DeviceAIRecognitionState: Sendable, Equatable {
    case analyzing
    case recognized(DeviceAIRecognition)
    case insufficient(String)
    case refused(String)
    case failed(String)
}

extension DiscoveredNetworkDevice {
    func displayName(aiState: DeviceAIRecognitionState?) -> String {
        guard displayName == "Unknown Device",
              case .recognized(let recognition) = aiState else {
            return displayName
        }

        let suggestedName = recognition.suggestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        return suggestedName.isEmpty ? displayName : suggestedName
    }

    func systemImageName(aiState: DeviceAIRecognitionState?) -> String {
        if isRouter { return "wifi.router.fill" }
        if isLocalDevice { return "desktopcomputer" }

        guard displayName == "Unknown Device",
              case .recognized(let recognition) = aiState else {
            return "network"
        }

        let description = [
            recognition.category,
            recognition.suggestedName,
            recognition.likelyPurpose,
        ]
        .joined(separator: " ")
        .lowercased()

        let mappings: [([String], String)] = [
            (["printer", "scanner"], "printer.fill"),
            (["camera", "webcam"], "camera.fill"),
            (["television", "smart tv", "media player", "streaming"], "tv.fill"),
            (["speaker", "audio", "soundbar"], "hifispeaker.fill"),
            (["phone", "smartphone", "mobile"], "iphone"),
            (["tablet", "ipad"], "ipad"),
            (["laptop", "notebook"], "laptopcomputer"),
            (["computer", "desktop", "workstation", "server"], "desktopcomputer"),
            (["game", "console"], "gamecontroller.fill"),
            (["storage", "nas", "drive"], "externaldrive.fill"),
            (["watch", "wearable"], "applewatch"),
            (["light", "bulb", "lamp"], "lightbulb.fill"),
            (["thermostat", "climate"], "thermometer.medium"),
            (["router", "access point", "gateway", "mesh"], "wifi.router.fill"),
            (["hub", "bridge", "controller"], "point.3.connected.trianglepath.dotted"),
            (["sensor", "alarm", "security"], "sensor.fill"),
            (["appliance", "vacuum", "refrigerator", "oven", "washer"], "house.fill"),
        ]

        return mappings.first { keywords, _ in
            keywords.contains { description.contains($0) }
        }?.1 ?? "network"
    }
}

struct AIRecognitionInput: Codable, Sendable, Equatable {
    let itemID: String
    let hostname: String?
    let vendorName: String?
    let isRouter: Bool
    let isLocalDevice: Bool
    let responseTimeMilliseconds: Double?

    init(itemID: String, device: DiscoveredNetworkDevice) {
        self.itemID = itemID
        self.hostname = device.hostname
        self.vendorName = device.vendorName
        self.isRouter = device.isRouter
        self.isLocalDevice = device.isLocalDevice
        self.responseTimeMilliseconds = device.responseTimeMilliseconds.map {
            ($0 * 10).rounded() / 10
        }
    }
}

struct AIRecognitionBatcher {
    static func batches<T>(from values: [T], maximumSize: Int = 25) -> [[T]] {
        guard maximumSize > 0 else { return [] }
        return stride(from: 0, to: values.count, by: maximumSize).map {
            Array(values[$0..<min($0 + maximumSize, values.count)])
        }
    }
}

enum AIRecognitionError: LocalizedError, Sendable, Equatable {
    case missingAPIKey
    case invalidAPIKey
    case modelUnavailable
    case rateLimited
    case refused(String)
    case invalidResponse
    case unavailable(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your OpenAI API key in Settings before using AI recognition."
        case .invalidAPIKey:
            return "OpenAI rejected this API key. Replace it in Settings and try again."
        case .modelUnavailable:
            return "The configured OpenAI account cannot access gpt-5.4-mini."
        case .rateLimited:
            return "OpenAI rate-limited the request. Wait before trying again."
        case .refused(let reason):
            return reason.isEmpty ? "OpenAI declined to process this request." : reason
        case .invalidResponse:
            return "The AI method returned an unexpected response. No device details were changed."
        case .unavailable(let reason):
            return reason
        case .server(let message):
            return message.isEmpty ? "OpenAI could not complete the request." : message
        }
    }
}

protocol APIKeyStoring: Sendable {
    var hasKey: Bool { get }
    func loadKey() throws -> String?
    func saveKey(_ key: String) throws
    func removeKey() throws
}

final class OpenAIAPIKeyStore: APIKeyStoring, @unchecked Sendable {
    static let shared = OpenAIAPIKeyStore()

    private let service: String
    private let account: String

    init(
        service: String = "com.adisapir.MacSpeedMonitor.openai",
        account: String = "OpenAI API Key"
    ) {
        self.service = service
        self.account = account
    }

    var hasKey: Bool {
        (try? loadKey())??.isEmpty == false
    }

    func loadKey() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8)
        else { throw KeychainError(status) }
        return key
    }

    func saveKey(_ key: String) throws {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw AIRecognitionError.missingAPIKey }
        let data = Data(normalized.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw KeychainError(updateStatus) }

        var addition = baseQuery
        addition[kSecValueData as String] = data
        addition[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addition as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(addStatus) }
    }

    func removeKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private struct KeychainError: LocalizedError {
        let status: OSStatus

        init(_ status: OSStatus) { self.status = status }

        var errorDescription: String? {
            SecCopyErrorMessageString(status, nil) as String?
                ?? "Keychain operation failed (\(status))."
        }
    }
}

protocol AIRecognitionProviding: Sendable {
    var method: AIRecognitionMethod { get }
    var availability: AIRecognitionAvailability { get }
    var maximumBatchSize: Int { get }
    func recognize(_ inputs: [AIRecognitionInput]) async throws -> [DeviceAIRecognition]
}

struct OpenAIRecognitionProvider: AIRecognitionProviding, Sendable {
    static let model = "gpt-5.4-mini"
    static let responsesURL = URL(string: "https://api.openai.com/v1/responses")!
    static let modelURL = URL(string: "https://api.openai.com/v1/models/\(model)")!

    private let session: URLSession
    private let keyStore: any APIKeyStoring

    init(session: URLSession = .shared, keyStore: any APIKeyStoring = OpenAIAPIKeyStore.shared) {
        self.session = session
        self.keyStore = keyStore
    }

    var hasAPIKey: Bool { keyStore.hasKey }
    var method: AIRecognitionMethod { .openAI }
    var availability: AIRecognitionAvailability {
        hasAPIKey
            ? .available
            : .unavailable("Add an OpenAI API key in Settings before using AI recognition.")
    }
    var maximumBatchSize: Int { 25 }

    func testConnection() async throws {
        var request = URLRequest(url: Self.modelURL)
        request.httpMethod = "GET"
        try authorize(&request)
        let (_, response) = try await session.data(for: request)
        try validate(response)
    }

    func recognize(_ inputs: [AIRecognitionInput]) async throws -> [DeviceAIRecognition] {
        guard !inputs.isEmpty else { return [] }
        var request = URLRequest(url: Self.responsesURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try authorize(&request)

        let inputData = try JSONEncoder().encode(inputs)
        let inputJSON = String(decoding: inputData, as: UTF8.self)
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(inputJSON: inputJSON))

        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        let envelope = try JSONDecoder().decode(OpenAIResponseEnvelope.self, from: data)
        if let refusal = envelope.refusalText {
            throw AIRecognitionError.refused(refusal)
        }
        guard let text = envelope.outputText,
              let resultData = text.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RecognitionEnvelope.self, from: resultData)
        else { throw AIRecognitionError.invalidResponse }

        let expectedIDs = Set(inputs.map(\.itemID))
        let actualIDs = decoded.recognitions.map(\.itemID)
        guard Set(actualIDs) == expectedIDs, Set(actualIDs).count == actualIDs.count else {
            throw AIRecognitionError.invalidResponse
        }
        return decoded.recognitions.map {
            DeviceAIRecognition(
                itemID: $0.itemID,
                suggestedName: $0.suggestedName,
                category: $0.category,
                likelyPurpose: $0.likelyPurpose,
                confidence: $0.confidence,
                rationale: $0.rationale,
                limitations: $0.limitations,
                method: .openAI
            )
        }
    }

    private func authorize(_ request: inout URLRequest) throws {
        guard let key = try keyStore.loadKey(), !key.isEmpty else {
            throw AIRecognitionError.missingAPIKey
        }
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 45
    }

    private func validate(_ response: URLResponse, data: Data = Data()) throws {
        guard let http = response as? HTTPURLResponse else { throw AIRecognitionError.invalidResponse }
        switch http.statusCode {
        case 200..<300:
            return
        case 401, 403:
            throw AIRecognitionError.invalidAPIKey
        case 404:
            throw AIRecognitionError.modelUnavailable
        case 429:
            throw AIRecognitionError.rateLimited
        default:
            let message = (try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data))?.error.message ?? ""
            throw AIRecognitionError.server(message)
        }
    }

    private func requestBody(inputJSON: String) -> [String: Any] {
        [
            "model": Self.model,
            "store": false,
            "max_output_tokens": 2_000,
            "input": [
                [
                    "role": "developer",
                    "content": """
                    Classify local network devices only from the supplied redacted metadata,
                    including a discovered hostname when available.
                    Analyze this network scan to determine exactly what device it is, and provide your best guess along with a confidence level.
                    """,
                ],
                ["role": "user", "content": inputJSON],
            ],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "device_recognitions",
                    "strict": true,
                    "schema": responseSchema,
                ],
            ],
        ]
    }

    private var responseSchema: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "recognitions": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "properties": [
                            "itemID": ["type": "string"],
                            "suggestedName": ["type": "string"],
                            "category": ["type": "string"],
                            "likelyPurpose": ["type": "string"],
                            "confidence": ["type": "string", "enum": ["low", "medium", "high"]],
                            "rationale": ["type": "string"],
                            "limitations": ["type": "string"],
                        ],
                        "required": [
                            "itemID", "suggestedName", "category", "likelyPurpose",
                            "confidence", "rationale", "limitations",
                        ],
                    ],
                ],
            ],
            "required": ["recognitions"],
        ]
    }
}

struct UnavailableAIRecognitionProvider: AIRecognitionProviding {
    let method: AIRecognitionMethod
    let reason: String

    var availability: AIRecognitionAvailability { .unavailable(reason) }
    var maximumBatchSize: Int { 1 }

    func recognize(_ inputs: [AIRecognitionInput]) async throws -> [DeviceAIRecognition] {
        throw AIRecognitionError.unavailable(reason)
    }
}

enum AIRecognitionProviderFactory {
    static func providers() -> [AIRecognitionMethod: any AIRecognitionProviding] {
        var providers: [AIRecognitionMethod: any AIRecognitionProviding] = [
            .openAI: OpenAIRecognitionProvider(),
        ]
        if #available(macOS 26.0, *) {
            providers[.appleOnDevice] = AppleFoundationModelsRecognitionProvider()
        } else {
            providers[.appleOnDevice] = UnavailableAIRecognitionProvider(
                method: .appleOnDevice,
                reason: "Apple On-Device recognition requires macOS 26 or later."
            )
        }
        return providers
    }
}

private struct RecognitionEnvelope: Decodable {
    let recognitions: [DeviceAIRecognition]
}

private struct OpenAIResponseEnvelope: Decodable {
    let output: [OutputItem]

    struct OutputItem: Decodable {
        let content: [Content]?
    }

    struct Content: Decodable {
        let type: String
        let text: String?
        let refusal: String?
    }

    var outputText: String? {
        output.lazy.compactMap(\.content).joined().first(where: { $0.type == "output_text" })?.text
    }

    var refusalText: String? {
        output.lazy.compactMap(\.content).joined().first(where: { $0.type == "refusal" })?.refusal
    }
}

private struct OpenAIErrorEnvelope: Decodable {
    struct APIError: Decodable { let message: String }
    let error: APIError
}

extension DiscoveredNetworkDevice {
    var aiIdentity: String { macAddress ?? ipv4Address }
    var isUnknownForAIRecognition: Bool { hostname == nil && !isRouter && !isLocalDevice }
    var isEligibleForAIRecognition: Bool { !isRouter && !isLocalDevice }
}

// MARK: - Persistent Device History

struct PersistedDeviceRecord: Codable, Sendable, Equatable {
    let macAddress: String
    var lastKnownIPv4Address: String
    var hostname: String?
    var vendorName: String?
    var responseTimeMilliseconds: Double?
    var isRouter: Bool
    var isLocalDevice: Bool
    var lastSeenAt: Date
    var aiRecognition: DeviceAIRecognition?

    init?(
        device: DiscoveredNetworkDevice,
        aiRecognition: DeviceAIRecognition?
    ) {
        guard let macAddress = device.macAddress else { return nil }
        self.macAddress = macAddress
        self.lastKnownIPv4Address = device.ipv4Address
        self.hostname = device.hostname
        self.vendorName = device.vendorName
        self.responseTimeMilliseconds = device.responseTimeMilliseconds
        self.isRouter = device.isRouter
        self.isLocalDevice = device.isLocalDevice
        self.lastSeenAt = device.lastSeenAt
        self.aiRecognition = aiRecognition
    }

    func enriching(_ device: DiscoveredNetworkDevice) -> DiscoveredNetworkDevice {
        var enriched = device
        enriched.hostname = device.hostname ?? hostname
        enriched.vendorName = device.vendorName ?? vendorName
        enriched.responseTimeMilliseconds = device.responseTimeMilliseconds ?? responseTimeMilliseconds
        enriched.isRouter = device.isRouter || isRouter
        enriched.isLocalDevice = device.isLocalDevice || isLocalDevice
        return enriched
    }
}

protocol DeviceHistoryStoring: Sendable {
    func load() throws -> [String: PersistedDeviceRecord]
    func save(_ records: [String: PersistedDeviceRecord]) throws
    func remove() throws
}

final class LocalDeviceHistoryStore: DeviceHistoryStoring, @unchecked Sendable {
    static let shared = LocalDeviceHistoryStore()
    static let currentVersion = 1

    let fileURL: URL

    init(fileURL: URL = LocalDeviceHistoryStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    func load() throws -> [String: PersistedDeviceRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(DeviceHistoryFile.self, from: data)
        guard file.version == Self.currentVersion else { return [:] }
        return Dictionary(uniqueKeysWithValues: file.records.map { ($0.macAddress, $0) })
    }

    func save(_ records: [String: PersistedDeviceRecord]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let file = DeviceHistoryFile(
            version: Self.currentVersion,
            records: records.values.sorted { $0.macAddress < $1.macAddress }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(file).write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    func remove() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private static var defaultFileURL: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return applicationSupport
            .appendingPathComponent("MacSpeedMonitor", isDirectory: true)
            .appendingPathComponent("device-history.json")
    }

    private struct DeviceHistoryFile: Codable {
        let version: Int
        let records: [PersistedDeviceRecord]
    }
}
