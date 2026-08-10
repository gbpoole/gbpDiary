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
}

nonisolated enum ChatPromptBuilder {
    static func build(question: String, rankedChunks: [ChatRankedChunk], history: [ChatHistoryMessage],
                      maxHistoryMessages: Int = 6, maxHistoryCharacters: Int = 3_000,
                      maxSourceCharacters: Int = 8_000) -> ChatPromptBundle {
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

        var sections = ["Answer using only the supplied sources. Cite factual claims with source labels such as [S1]. If the sources do not answer the question, say so."]
        if !recentHistory.isEmpty {
            let lines = recentHistory.map { "\($0.role == .user ? "User" : "Assistant"): \($0.text)" }
            sections.append("Recent conversation:\n" + lines.joined(separator: "\n"))
        }
        if !sources.isEmpty {
            let rendered = sources.map { source in
                "[\(source.label)] \(source.chunk.source.displayLabel)\n\(source.chunk.text)"
            }
            sections.append("Sources:\n" + rendered.joined(separator: "\n\n"))
        }
        sections.append("Question: \(question.trimmingCharacters(in: .whitespacesAndNewlines))")
        return ChatPromptBundle(prompt: sections.joined(separator: "\n\n"), sources: sources)
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

nonisolated struct ChatCitationValidation: Equatable, Sendable {
    let citedLabels: [String]
    let unknownLabels: [String]
    let requiresCitation: Bool

    var isValid: Bool { unknownLabels.isEmpty && (!requiresCitation || !citedLabels.isEmpty) }
}

nonisolated enum ChatCitationValidator {
    static func validate(answer: String, allowedLabels: Set<String>) -> ChatCitationValidation {
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
            requiresCitation: !allowedLabels.isEmpty
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
}

nonisolated struct ChatAnswer: Equatable, Sendable {
    let text: String
    let citations: [ChatSourceReference]
    let summaryCandidates: [ChatSummaryCandidate]
}

nonisolated enum ChatAnswerError: Error, Equatable, Sendable {
    case modelUnavailable
    case emptyAnswer
    case invalidCitations([String])
}

nonisolated protocol ChatAnswering {
    var isAvailable: Bool { get }
    func answer(request: ChatAnswerRequest) async throws -> ChatAnswer
}
