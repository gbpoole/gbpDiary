import Foundation

nonisolated enum ChatRole: String, Codable, Hashable, Sendable {
    case user
    case assistant
}

nonisolated struct ChatHistoryMessage: Codable, Equatable, Sendable {
    let role: ChatRole
    let text: String
}

nonisolated struct ChatPromptSource: Equatable, Sendable {
    let label: String
    let chunk: ChatRetrievalChunk
}

nonisolated struct ChatPromptBundle: Equatable, Sendable {
    let prompt: String
    let sources: [ChatPromptSource]
    let requiresCitation: Bool
}

nonisolated enum ChatPromptBuilder {
    static func build(question: String, rankedChunks: [ChatRankedChunk], history: [ChatHistoryMessage],
                      maxHistoryMessages: Int = 6, maxHistoryCharacters: Int = 3_000,
                      maxSourceCharacters: Int = 8_000,
                      allowsUncitedTransformation: Bool = false,
                      wantsOverview: Bool = false,
                      computedTotals: String? = nil,
                      requiresCitation requiresCitationOverride: Bool? = nil) -> ChatPromptBundle {
        let recentHistory = boundedHistory(history, maxMessages: maxHistoryMessages, maxCharacters: maxHistoryCharacters)
        var sourceCharacters = 0
        var sources: [ChatPromptSource] = []
        for ranked in rankedChunks {
            guard sourceCharacters < maxSourceCharacters else { break }
            let remaining = maxSourceCharacters - sourceCharacters
            let text = String(ranked.chunk.text.prefix(remaining))
            guard !text.isEmpty else { continue }
            var chunk = ranked.chunk
            if text != chunk.text {
                chunk = ChatRetrievalChunk(source: chunk.source, index: chunk.index, text: text)
            }
            sources.append(ChatPromptSource(label: "S\(sources.count + 1)", chunk: chunk))
            sourceCharacters += text.count
        }

        let hasTotals = (computedTotals?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        let shape = wantsOverview
            ? "Write a short prose overview (a few sentences), not a list."
            : "Write a short bulleted list of themed points. Combine several sources into each point; never list sources one by one."
        // Only mention time totals when a computed block is actually supplied — otherwise the model
        // invents an empty "Computed time totals" section.
        let totalsInstruction = hasTotals
            ? " A 'Computed time totals' block is supplied below. Reproduce that block once, verbatim, as a single line at the very end of your answer. Do NOT place totals inside the per-project sections, do NOT split the block across sections, and do NOT compute your own running totals or subtotals."
            : " Do not report or invent any time totals or hours; none were requested."
        let groundingInstruction = allowsUncitedTransformation
            ? "Transform only the material in the recent conversation and supplied sources. Do not add facts. Inline citations are optional in the transformed output."
            : "Answer using only the supplied sources, synthesising them into a real summary — group related information and combine multiple sources into each point rather than describing each source in turn. "
              + shape
              + " If the material spans more than one project, group your answer by project (a short lead-in per project) unless the question asks for a single combined view."
              + totalsInstruction
              + " When a source is marked with higher importance, lead with it."
              + " Cite the key supporting sources with labels such as [S1] where useful — not every sentence. If the sources do not answer the question, say so."
        var sections = [groundingInstruction]
        if !recentHistory.isEmpty {
            let lines = recentHistory.map { "\($0.role == .user ? "User" : "Assistant"): \($0.text)" }
            sections.append("Recent conversation:\n" + lines.joined(separator: "\n"))
        }
        if let computedTotals, !computedTotals.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(computedTotals)
        }
        if !sources.isEmpty {
            let rendered = sources.map { source in
                "[\(source.label)] \(source.chunk.source.displayLabel)\n\(source.chunk.text)"
            }
            sections.append("Sources:\n" + rendered.joined(separator: "\n\n"))
        }
        sections.append("Question: \(question.trimmingCharacters(in: .whitespacesAndNewlines))")
        return ChatPromptBundle(prompt: sections.joined(separator: "\n\n"), sources: sources,
                                requiresCitation: requiresCitationOverride ?? !allowsUncitedTransformation)
    }

    static func boundedHistory(_ history: [ChatHistoryMessage], maxMessages: Int,
                               maxCharacters: Int) -> [ChatHistoryMessage] {
        guard maxMessages > 0, maxCharacters > 0 else { return [] }
        var result: [ChatHistoryMessage] = []
        var used = 0
        for message in history.suffix(maxMessages).reversed() {
            let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let remaining = maxCharacters - used
            guard remaining > 0 else { break }
            let bounded = String(trimmed.suffix(remaining))
            result.append(ChatHistoryMessage(role: message.role, text: bounded))
            used += bounded.count
        }
        return result.reversed()
    }
}

nonisolated enum ChatFollowUpIntent {
    static func isTransformation(question: String, history: [ChatHistoryMessage]) -> Bool {
        guard history.contains(where: { $0.role == .assistant }) else { return false }
        let words = Set(normalizedWords(question))
        let references: Set<String> = ["above", "it", "material", "that", "these", "this"]
        let transformations: Set<String> = [
            "build", "draft", "expand", "joke", "make", "poem", "rephrase", "rewrite",
            "shorten", "summarise", "summarize", "turn"
        ]
        return !words.isDisjoint(with: references) && !words.isDisjoint(with: transformations)
    }

    static func retrievalQuery(question: String, history: [ChatHistoryMessage]) -> String {
        guard isTransformation(question: question, history: history),
              let priorQuestion = history.last(where: { $0.role == .user })?.text else { return question }
        return priorQuestion + " " + question
    }

    private static func normalizedWords(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}

nonisolated enum ChatCapabilityResponse {
    static let text = "I can search your local projects, tasks, people, institutions, meetings and minutes, notes, diary days, documents, stored email subjects and summaries, and supported attachment text. I answer with links to the workspace sources I used. Database Chat never reads email bodies; use Email Explorer to experiment with a selected email's summary."

    static func answer(for question: String) -> String? {
        let normalized = question.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let capabilityQuestions: Set<String> = [
            "help",
            "how can you help",
            "what can i ask you",
            "what can you do",
            "what do you do"
        ]
        return capabilityQuestions.contains(normalized) ? text : nil
    }
}

nonisolated struct ChatCitationValidation: Equatable, Sendable {
    let citedLabels: [String]
    let unknownLabels: [String]
    let requiresCitation: Bool

    var isValid: Bool { unknownLabels.isEmpty && (!requiresCitation || !citedLabels.isEmpty) }
}

nonisolated enum ChatCitationValidator {
    static func validate(answer: String, allowedLabels: Set<String>, requiresCitation: Bool? = nil) -> ChatCitationValidation {
        let pattern = #"\[([Ss]\d+)\]"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(answer.startIndex..<answer.endIndex, in: answer)
        var labels: [String] = []
        var seen = Set<String>()
        regex?.enumerateMatches(in: answer, range: range) { match, _, _ in
            guard let match, let swiftRange = Range(match.range(at: 1), in: answer) else { return }
            let label = answer[swiftRange].uppercased()
            if seen.insert(label).inserted { labels.append(label) }
        }
        return ChatCitationValidation(
            citedLabels: labels.filter(allowedLabels.contains),
            unknownLabels: labels.filter { !allowedLabels.contains($0) },
            requiresCitation: requiresCitation ?? !allowedLabels.isEmpty
        )
    }
}

nonisolated struct ChatSummaryCandidate: Equatable, Sendable {
    let sourceKey: ChatSourceKey
    let summary: String
}

nonisolated enum ChatSummaryAdoption {
    static func adopting(_ candidate: ChatSummaryCandidate,
                         in documents: [ChatRetrievalDocument]) -> [ChatRetrievalDocument] {
        let summary = candidate.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return documents }
        return documents.map { document in
            guard document.id == candidate.sourceKey else { return document }
            var updated = document
            updated.summary = summary
            return updated
        }
    }
}

nonisolated struct ChatAnswerRequest: Equatable, Sendable {
    let prompt: ChatPromptBundle
    let fallbackCitations: [ChatSourceReference]

    init(prompt: ChatPromptBundle, fallbackCitations: [ChatSourceReference] = []) {
        self.prompt = prompt
        self.fallbackCitations = fallbackCitations
    }
}

nonisolated struct ChatAnswer: Equatable, Sendable {
    let text: String
    let citations: [ChatSourceReference]
    let summaryCandidates: [ChatSummaryCandidate]
}

nonisolated enum ChatAnswerAssembly {
    static func make(text: String, prompt: ChatPromptBundle,
                     fallbackCitations: [ChatSourceReference] = []) throws -> ChatAnswer {
        let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { throw ChatAnswerError.emptyAnswer }

        let byLabel = Dictionary(uniqueKeysWithValues: prompt.sources.map { ($0.label, $0.chunk.source) })
        let validation = ChatCitationValidator.validate(
            answer: answer,
            allowedLabels: Set(byLabel.keys),
            requiresCitation: prompt.requiresCitation
        )
        guard validation.isValid else { throw ChatAnswerError.invalidCitations(validation.unknownLabels) }
        let mappedCitations = validation.citedLabels.compactMap { byLabel[$0] }
        return ChatAnswer(
            text: answer,
            citations: mappedCitations.isEmpty ? fallbackCitations : mappedCitations,
            summaryCandidates: []
        )
    }
}

nonisolated enum ChatAnswerError: Error, Equatable, Sendable, LocalizedError {
    case modelUnavailable
    case emptyAnswer
    case invalidCitations([String])

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            return "The on-device language model is unavailable."
        case .emptyAnswer:
            return "The on-device model returned an empty answer."
        case .invalidCitations(let labels) where labels.isEmpty:
            return "The on-device model did not cite any supplied workspace source."
        case .invalidCitations(let labels):
            return "The on-device model cited unknown workspace sources: \(labels.joined(separator: ", "))."
        }
    }
}

nonisolated protocol ChatAnswering {
    var isAvailable: Bool { get }
    var unavailableReason: String? { get }
    func answer(request: ChatAnswerRequest) async throws -> ChatAnswer
}

extension ChatAnswering {
    var unavailableReason: String? { nil }
}
