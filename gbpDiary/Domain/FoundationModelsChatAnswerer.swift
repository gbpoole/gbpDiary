import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct FoundationModelsChatAnswerer: ChatAnswering {
    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(.deviceNotEligible):
                return "This Mac does not support Apple Intelligence."
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Turn on Apple Intelligence in System Settings to generate answers on-device."
            case .unavailable(.modelNotReady):
                return "The on-device model is still downloading. Local source search remains available."
            case .unavailable:
                return "The on-device model is unavailable right now."
            }
        }
        #endif
        return "On-device answers require macOS 26 with Apple Intelligence."
    }

    /// Loads the on-device model into memory ahead of use (fire-and-forget) so the first real answer/scope
    /// call doesn't pay cold-start latency. Safe to call repeatedly; a no-op when the model is unavailable.
    func prewarm() {
        #if canImport(FoundationModels)
        if #available(macOS 26, *), SystemLanguageModel.default.availability == .available {
            LanguageModelSession().prewarm()
        }
        #endif
    }

    func answer(request: ChatAnswerRequest) async throws -> ChatAnswer {
        #if canImport(FoundationModels)
        if #available(macOS 26, *), SystemLanguageModel.default.availability == .available {
            let instructions = "Answer questions from local context only. Return plain text with supplied [S#] citations after factual claims. Never invent a source label or return JSON."
            let session = LanguageModelSession(instructions: instructions)
            let options = GenerationOptions(temperature: 0.2, maximumResponseTokens: 600)
            let response = try await session.respond(to: request.prompt.prompt, options: options)
            return try ChatAnswerAssembly.make(
                text: response.content,
                prompt: request.prompt,
                fallbackCitations: request.fallbackCitations
            )
        }
        #endif
        throw ChatAnswerError.modelUnavailable
    }
}
