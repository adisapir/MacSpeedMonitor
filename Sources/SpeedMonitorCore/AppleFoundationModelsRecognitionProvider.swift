#if canImport(FoundationModels)
import Foundation
import FoundationModels

@available(macOS 26.0, *)
@Generable
private struct AppleGeneratedDeviceRecognition {
    @Guide(description: "Whether the device type can be cautiously recognized from the supplied metadata")
    var recognized: Bool

    @Guide(description: "A short cautious device name, without claiming an exact model unless supported by evidence")
    var suggestedName: String

    @Guide(description: "A short device category such as Speaker, Printer, Camera, Computer, TV, Storage, or IoT")
    var category: String

    @Guide(description: "A concise description of the device's likely purpose")
    var likelyPurpose: String

    @Guide(description: "One of: low, medium, high")
    var confidence: String

    @Guide(description: "A concise explanation based only on the supplied metadata")
    var rationale: String

    @Guide(description: "What remains uncertain about the recognition")
    var limitations: String
}

@available(macOS 26.0, *)
struct AppleFoundationModelsRecognitionProvider: AIRecognitionProviding {
    var method: AIRecognitionMethod { .appleOnDevice }
    var maximumBatchSize: Int { 1 }

    var availability: AIRecognitionAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable("This Mac does not support Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Turn on Apple Intelligence in System Settings to use on-device recognition.")
        case .unavailable(.modelNotReady):
            return .unavailable("The Apple Intelligence model is downloading or not ready yet.")
        case .unavailable:
            return .unavailable("Apple On-Device recognition is currently unavailable.")
        }
    }

    func recognize(_ inputs: [AIRecognitionInput]) async throws -> [DeviceAIRecognition] {
        guard availability.isAvailable else {
            throw AIRecognitionError.unavailable(availability.message)
        }

        var results: [DeviceAIRecognition] = []
        results.reserveCapacity(inputs.count)
        for input in inputs {
            try Task.checkCancellation()
            let session = LanguageModelSession(instructions: AIRecognitionPrompt.instructions)
            let data = try JSONEncoder().encode(input)
            let prompt = "Device metadata: \(String(decoding: data, as: UTF8.self))"
            let response = try await session.respond(
                to: prompt,
                generating: AppleGeneratedDeviceRecognition.self
            )
            let generated = response.content
            let confidence = AIRecognitionConfidence(rawValue: generated.confidence.lowercased()) ?? .low
            results.append(DeviceAIRecognition(
                itemID: input.itemID,
                suggestedName: generated.recognized ? generated.suggestedName : "Unable to recognize",
                category: generated.category,
                likelyPurpose: generated.likelyPurpose,
                confidence: confidence,
                rationale: generated.rationale,
                limitations: generated.limitations,
                method: .appleOnDevice
            ))
        }
        return results
    }
}
#endif
