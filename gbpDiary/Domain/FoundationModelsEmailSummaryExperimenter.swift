import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct FoundationModelsEmailSummaryExperimenter: EmailSummaryExperimenting {
    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    func generate(_ request: EmailSummaryExperimentRequest) async throws -> String {
        let body = request.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw EmailSummaryError.emptyBody }

        #if canImport(FoundationModels)
        if #available(macOS 26, *), SystemLanguageModel.default.availability == .available {
            let instructions = """
            You experiment with concise email summaries for the reader's diary.
            The EMAIL is the sole evidence for what the email says. BACKGROUND may clarify identities and terminology, but never introduce a background fact as though it appeared in the email.
            Refer to the reader as "you". Omit greetings, signatures, titles, affiliations, preambles, and markdown. Output only one or two factual sentences.
            """
            var prompt = EmailSummaryPrompt.build(context: request.context,
                                                  subject: request.subject, body: body)
            let custom = request.experimentalInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
            if !custom.isEmpty { prompt += "\n\nEXPERIMENTAL EMPHASIS:\n\(custom)" }
            if !request.backgroundSources.isEmpty {
                let background = request.backgroundSources.map {
                    "[\($0.label)] \($0.chunk.source.displayLabel)\n\($0.chunk.text)"
                }.joined(separator: "\n\n")
                prompt += "\n\nBACKGROUND (clarification only):\n\(background)"
            }
            let session = LanguageModelSession(instructions: instructions)
            let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: 120)
            let response = try await session.respond(to: prompt, options: options)
            return EmailSummaryText.clean(response.content)
        }
        #endif
        throw EmailSummaryError.modelUnavailable
    }
}
