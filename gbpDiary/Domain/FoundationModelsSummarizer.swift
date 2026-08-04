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

    func summarize(context: SummaryContext, subject: String, body: String) async throws -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EmailSummaryError.emptyBody }

        #if canImport(FoundationModels)
        if #available(macOS 26, *), SystemLanguageModel.default.availability == .available {
            let session = LanguageModelSession(instructions: EmailSummaryPrompt.instructions)
            let prompt = EmailSummaryPrompt.build(context: context, subject: subject, body: trimmed)
            // Guided generation + low temperature + a hard token cap → strict, concise, consistent output.
            let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: 90)
            let response = try await session.respond(to: prompt, generating: EmailSummaryOutput.self, options: options)
            return EmailSummaryText.clean(response.content.summary)
        }
        #endif
        throw EmailSummaryError.modelUnavailable
    }
}

#if canImport(FoundationModels)
@available(macOS 26, *)
@Generable
struct EmailSummaryOutput {
    @Guide(description: "One or two concise sentences (≤ ~40 words) for a diary, referring to the reader as \"you\"; no titles, affiliations, signatures, or markdown.")
    var summary: String
}
#endif
