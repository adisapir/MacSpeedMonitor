import Foundation

final class GeminiAPIKeyStore: KeychainAPIKeyStore, @unchecked Sendable {
    static let shared = GeminiAPIKeyStore()

    init(
        service: String = "com.adisapir.MacSpeedMonitor.gemini",
        account: String = "Google Gemini API Key"
    ) {
        super.init(service: service, account: account)
    }
}

struct GeminiRecognitionProvider: APIKeyBackedAIRecognitionProviding, Sendable {
    static let model = "gemini-3.5-flash"
    static let generateContentURL = URL(
        string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
    )!
    static let modelURL = URL(
        string: "https://generativelanguage.googleapis.com/v1beta/models/\(model)"
    )!

    private let session: URLSession
    private let keyStore: any APIKeyStoring

    init(session: URLSession = .shared, keyStore: any APIKeyStoring = GeminiAPIKeyStore.shared) {
        self.session = session
        self.keyStore = keyStore
    }

    var hasAPIKey: Bool { keyStore.hasKey }
    var method: AIRecognitionMethod { .googleGemini }
    var availability: AIRecognitionAvailability { .available }
    var maximumBatchSize: Int { 25 }

    func debugPrompt(for inputs: [AIRecognitionInput]) throws -> AIRecognitionDebugPrompt {
        let inputJSON = String(decoding: try JSONEncoder().encode(inputs), as: UTF8.self)
        return AIRecognitionDebugPrompt(
            agentDescription: "\(method.displayName) (\(Self.model))",
            prompt: """
            systemInstruction:
            \(AIRecognitionPrompt.instructions)

            user:
            \(inputJSON)
            """
        )
    }

    func testConnection() async throws {
        var request = URLRequest(url: Self.modelURL)
        request.httpMethod = "GET"
        try authorize(&request)
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
    }

    func recognize(_ inputs: [AIRecognitionInput]) async throws -> [DeviceAIRecognition] {
        guard !inputs.isEmpty else { return [] }
        var request = URLRequest(url: Self.generateContentURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try authorize(&request)

        let inputJSON = String(decoding: try JSONEncoder().encode(inputs), as: UTF8.self)
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(inputJSON: inputJSON))
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)

        let envelope = try JSONDecoder().decode(GeminiResponseEnvelope.self, from: data)
        if let refusal = envelope.refusalReason { throw AIRecognitionError.refused(refusal) }
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
                method: .googleGemini
            )
        }
    }

    private func authorize(_ request: inout URLRequest) throws {
        guard let key = try keyStore.loadKey(), !key.isEmpty else {
            throw AIRecognitionError.missingAPIKey
        }
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 45
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw AIRecognitionError.invalidResponse }
        let message = (try? JSONDecoder().decode(GeminiErrorEnvelope.self, from: data))?.error.message ?? ""
        switch http.statusCode {
        case 200..<300: return
        case 400: throw AIRecognitionError.server(message)
        case 401, 403: throw AIRecognitionError.invalidAPIKey
        case 404: throw AIRecognitionError.modelUnavailable
        case 429: throw AIRecognitionError.rateLimited
        default:
            throw AIRecognitionError.server(message)
        }
    }

    private func requestBody(inputJSON: String) -> [String: Any] {
        [
            "systemInstruction": ["parts": [["text": AIRecognitionPrompt.instructions]]],
            "contents": [["role": "user", "parts": [["text": inputJSON]]]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": GeminiSchemaAdapter.adapt(AIRecognitionPrompt.responseSchema),
            ],
        ]
    }
}

enum GeminiSchemaAdapter {
    static func adapt(_ schema: [String: Any]) -> [String: Any] {
        removingUnsupportedFields(from: schema) as? [String: Any] ?? schema
    }

    private static func removingUnsupportedFields(from value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, entry in
                guard entry.key != "additionalProperties" else { return }
                result[entry.key] = removingUnsupportedFields(from: entry.value)
            }
        }
        if let array = value as? [Any] {
            return array.map(removingUnsupportedFields)
        }
        return value
    }
}

private struct GeminiResponseEnvelope: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable { let text: String? }
            let parts: [Part]
        }
        let content: Content?
        let finishReason: String?
    }
    struct PromptFeedback: Decodable { let blockReason: String? }

    let candidates: [Candidate]?
    let promptFeedback: PromptFeedback?

    var outputText: String? {
        candidates?.lazy.compactMap(\.content).flatMap(\.parts).compactMap(\.text).first
    }

    var refusalReason: String? {
        if let reason = promptFeedback?.blockReason { return "Gemini declined the request: \(reason)." }
        guard let reason = candidates?.first?.finishReason, reason != "STOP" else { return nil }
        return "Gemini stopped the request: \(reason)."
    }
}

private struct GeminiErrorEnvelope: Decodable {
    struct APIError: Decodable { let message: String }
    let error: APIError
}
