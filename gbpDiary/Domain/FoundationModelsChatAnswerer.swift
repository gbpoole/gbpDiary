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

    func answer(request: ChatAnswerRequest) async throws -> ChatAnswer {
        #if canImport(FoundationModels)
        if #available(macOS 26, *), SystemLanguageModel.default.availability == .available {
            let instructions = "Answer questions from local context only. Use supplied [S#] citations. Never invent a source label. Return optional concise source summaries only when the source itself supports them."
            let session = LanguageModelSession(instructions: instructions)
            let options = GenerationOptions(temperature: 0.2, maximumResponseTokens: 600)
            let response = try await session.respond(
                to: request.prompt.prompt,
                generating: FoundationModelsChatOutput.self,
                options: options
            )
            let text = response.content.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw ChatAnswerError.emptyAnswer }

            let byLabel = Dictionary(uniqueKeysWithValues: request.prompt.sources.map { ($0.label, $0.chunk.source) })
            let validation = ChatCitationValidator.validate(answer: text, allowedLabels: Set(byLabel.keys))
            guard validation.isValid else { throw ChatAnswerError.invalidCitations(validation.unknownLabels) }
            let citations = validation.citedLabels.compactMap { byLabel[$0] }
            let summaries = response.content.summaries.compactMap { output -> ChatSummaryCandidate? in
                let label = output.sourceLabel.uppercased()
                guard let source = byLabel[label] else { return nil }
                let summary = output.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                return summary.isEmpty ? nil : ChatSummaryCandidate(sourceKey: source.key, summary: summary)
            }
            return ChatAnswer(text: text, citations: citations, summaryCandidates: summaries)
        }
        #endif
        throw ChatAnswerError.modelUnavailable
    }
}

#if canImport(FoundationModels)
@available(macOS 26, *)
@Generable
private struct FoundationModelsChatSummaryOutput {
    @Guide(description: "A supplied source label such as S1.")
    var sourceLabel: String

    @Guide(description: "A concise factual summary of that source, without markdown.")
    var summary: String
}

@available(macOS 26, *)
@Generable
private struct FoundationModelsChatOutput {
    @Guide(description: "A direct answer grounded only in supplied sources, with [S#] citations after factual claims.")
    var answer: String

    @Guide(description: "Zero or more useful source summary candidates. Do not summarize a source unless warranted.")
    var summaries: [FoundationModelsChatSummaryOutput]
}
#endif
