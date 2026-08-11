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
        #expect(bundle.requiresCitation)
    }

    @Test func followUpTransformation_usesPriorQuestionAndAllowsCitationFreeOutput() throws {
        let history = [
            ChatHistoryMessage(role: .user, text: "What happened to the train service?"),
            ChatHistoryMessage(role: .assistant, text: "The service was severely disrupted. [S1]")
        ]
        let question = "Can you tke this material and build a joke from it?"
        #expect(ChatFollowUpIntent.isTransformation(question: question, history: history))
        #expect(ChatFollowUpIntent.retrievalQuery(question: question, history: history)
            .hasPrefix("What happened to the train service?"))

        let source = ranked(0, text: "The trains completely imploded today.").chunk.source
        let bundle = ChatPromptBuilder.build(
            question: question,
            rankedChunks: [ranked(0, text: "The trains completely imploded today.")],
            history: history,
            allowsUncitedTransformation: true
        )
        #expect(!bundle.requiresCitation)
        #expect(bundle.prompt.contains("Inline citations are optional"))
        let answer = try ChatAnswerAssembly.make(
            text: "The timetable finally arrived, but the train didn't.",
            prompt: bundle,
            fallbackCitations: [source]
        )
        #expect(answer.citations == [source])
    }

    @Test func followUpTransformation_requiresContextAndRejectsUnknownCitations() {
        let question = "Turn this material into a joke"
        #expect(!ChatFollowUpIntent.isTransformation(question: question, history: []))
        let history = [ChatHistoryMessage(role: .assistant, text: "Grounded answer [S1]")]
        let bundle = ChatPromptBuilder.build(
            question: question,
            rankedChunks: [ranked(0, text: "Source")],
            history: history,
            allowsUncitedTransformation: true
        )
        #expect(throws: ChatAnswerError.invalidCitations(["S9"])) {
            try ChatAnswerAssembly.make(text: "A joke [S9]", prompt: bundle)
        }
    }

    @Test func capabilityResponse_handlesOnlyStandaloneHelpQuestions() {
        #expect(ChatCapabilityResponse.answer(for: "What can you do?") == ChatCapabilityResponse.text)
        #expect(ChatCapabilityResponse.answer(for: "  HOW can you help! ") == ChatCapabilityResponse.text)
        #expect(ChatCapabilityResponse.answer(for: "help") == ChatCapabilityResponse.text)
        #expect(ChatCapabilityResponse.answer(for: "What can you do about Project Alpha?") == nil)
        #expect(ChatCapabilityResponse.answer(for: "What is due today?") == nil)
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

    @Test func answerAssembly_acceptsPlainTextAndMapsCitations() throws {
        let bundle = ChatPromptBuilder.build(
            question: "What changed?",
            rankedChunks: [ranked(0, text: "The deadline moved to Friday.")],
            history: []
        )
        let answer = try ChatAnswerAssembly.make(text: "  The deadline moved to Friday. [S1]\n", prompt: bundle)
        #expect(answer.text == "The deadline moved to Friday. [S1]")
        #expect(answer.citations == [bundle.sources[0].chunk.source])
        #expect(answer.summaryCandidates.isEmpty)
    }

    @Test func answerAssembly_rejectsEmptyMissingAndUnknownCitations() {
        let bundle = ChatPromptBuilder.build(
            question: "What changed?",
            rankedChunks: [ranked(0, text: "The deadline moved to Friday.")],
            history: []
        )
        #expect(throws: ChatAnswerError.emptyAnswer) {
            try ChatAnswerAssembly.make(text: "  ", prompt: bundle)
        }
        #expect(throws: ChatAnswerError.invalidCitations([])) {
            try ChatAnswerAssembly.make(text: "The deadline moved.", prompt: bundle)
        }
        #expect(throws: ChatAnswerError.invalidCitations(["S2"])) {
            try ChatAnswerAssembly.make(text: "The deadline moved. [S2]", prompt: bundle)
        }
    }


    @Test func answerErrors_haveActionableDescriptions() {
        #expect(ChatAnswerError.emptyAnswer.localizedDescription.contains("empty answer"))
        #expect(ChatAnswerError.invalidCitations([]).localizedDescription.contains("did not cite"))
        #expect(ChatAnswerError.invalidCitations(["S9"]).localizedDescription.contains("S9"))
        #expect(ChatAnswerError.modelUnavailable.localizedDescription.contains("unavailable"))
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
