import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// On-device email summariser backed by Apple's Foundation Models framework. Uses ONLY the on-device
// model (`SystemLanguageModel.default`) — no Private Cloud Compute, no network. Gated to macOS 26+
// with Apple Intelligence; on older OSes / ineligible devices `isAvailable` is false and the auto
// pass marks emails `.unavailable`.
struct FoundationModelsSummarizer: EmailSummarizing {
    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    /// A user-facing reason the model is unavailable, or nil when it's available.
    var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(.deviceNotEligible):
                return "This Mac doesn't support Apple Intelligence, so email can't be summarised."
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Turn on Apple Intelligence in System Settings to summarise email on-device."
            case .unavailable(.modelNotReady):
                return "The on-device model is still downloading — summaries will appear once it's ready."
            case .unavailable:
                return "The on-device model is unavailable right now."
            }
        }
        #endif
        return "On-device summaries need macOS 26 with Apple Intelligence."
    }

    func summarize(subject: String, from: String, body: String) async throws -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EmailSummaryError.emptyBody }

        #if canImport(FoundationModels)
        if #available(macOS 26, *), SystemLanguageModel.default.availability == .available {
            let session = LanguageModelSession(instructions: EmailSummaryPrompt.instructions)
            let prompt = EmailSummaryPrompt.build(subject: subject, from: from, body: trimmed)
            let response = try await session.respond(to: prompt)
            return EmailSummaryText.clean(response.content)
        }
        #endif
        throw EmailSummaryError.modelUnavailable
    }
}
