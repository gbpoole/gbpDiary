import Foundation
import Testing
@testable import gbpDiary

@Suite("Chat answer domain")
struct ChatAnswerDomainTests {
    private func ranked(_ index: Int, text: String, title: String = "Alpha") -> ChatRankedChunk {
        let source = ChatSourceReference(id: UUID(), kind: .note, title: title, detail: nil)
        return ChatRankedChunk(
            chunk: ChatRetrievalChunk(source: source, index: index, text: text),
            score: 1,
            lexicalScore: 1,
            semanticScore: nil
        )
    }

    @Test func boundedHistory_keepsRecentMessagesWithinCharacterLimit() {
        let history = [
            ChatHistoryMessage(role: .user, text: "old"),
            ChatHistoryMessage(role: .assistant, text: "middle"),
            ChatHistoryMessage(role: .user, text: "newest")
        ]
        let result = ChatPromptBuilder.boundedHistory(history, maxMessages: 2, maxCharacters: 9)
        #expect(result == [
            ChatHistoryMessage(role: .assistant, text: "dle"),
            ChatHistoryMessage(role: .user, text: "newest")
        ])
    }

    @Test func promptBuilder_labelsSourcesAndBoundsContext() {
        let bundle = ChatPromptBuilder.build(
            question: "What changed?",
            rankedChunks: [ranked(0, text: "12345"), ranked(1, text: "abcdef", title: "Beta")],
            history: [],
            maxSourceCharacters: 8
        )
        #expect(bundle.sources.map(\.label) == ["S1", "S2"])
        #expect(bundle.sources.map(\.chunk.text) == ["12345", "abc"])
        #expect(bundle.prompt.contains("[S1] Note: Alpha"))
        #expect(bundle.prompt.contains("[S2] Note: Beta"))
        #expect(bundle.prompt.contains("Question: What changed?"))
    }

    @Test func citationValidator_acceptsKnownDedupesAndRejectsUnknown() {
        let valid = ChatCitationValidator.validate(answer: "Fact [S1], again [s1].", allowedLabels: ["S1"])
        #expect(valid.isValid)
        #expect(valid.citedLabels == ["S1"])

        let unknown = ChatCitationValidator.validate(answer: "Fact [S2].", allowedLabels: ["S1"])
        #expect(!unknown.isValid)
        #expect(unknown.unknownLabels == ["S2"])

        let missing = ChatCitationValidator.validate(answer: "Unsupported fact.", allowedLabels: ["S1"])
        #expect(!missing.isValid)
    }

    @Test func summaryAdoption_updatesMatchingDocumentOnlyAndIgnoresBlank() {
        let sharedID = UUID()
        let sourceA = ChatSourceReference(id: sharedID, kind: .note, title: "A", detail: nil)
        let sourceB = ChatSourceReference(id: sharedID, kind: .meeting, title: "B", detail: nil)
        let documents = [
            ChatRetrievalDocument(source: sourceA, markdown: "a"),
            ChatRetrievalDocument(source: sourceB, markdown: "b", summary: "Existing")
        ]
        let adopted = ChatSummaryAdoption.adopting(
            ChatSummaryCandidate(sourceKey: sourceA.key, summary: "  Concise summary.  "),
            in: documents
        )
        #expect(adopted[0].summary == "Concise summary.")
        #expect(adopted[1].summary == "Existing")
        #expect(ChatSummaryAdoption.adopting(ChatSummaryCandidate(sourceKey: sourceA.key, summary: "  "), in: documents) == documents)
    }
}
