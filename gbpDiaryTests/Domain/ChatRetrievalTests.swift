import Foundation
import Testing
@testable import gbpDiary

@Suite("Chat retrieval")
struct ChatRetrievalTests {
    private let source = ChatSourceReference(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        kind: .note,
        title: "Launch notes",
        detail: nil
    )

    @Test func sourceReference_buildsStableLabels() {
        #expect(source.displayLabel == "Note: Launch notes")
        #expect(ChatSourceReference(id: UUID(), kind: .meeting, title: "  ", detail: nil).displayLabel == "Meeting")
    }

    @Test func markdownNormalizer_removesSyntaxButKeepsMeaningfulLabels() {
        let markdown = """
        ---
        tag: private
        ---
        # Plan

        - [x] Read **the [brief](note://abc)**
        ![Diagram](attachment://def)
        """
        #expect(ChatMarkdownNormalizer.normalize(markdown) == "Plan\n\nRead the brief\nDiagram")
    }

    @Test func chunker_isDeterministicBoundedAndOverlapping() {
        let document = ChatRetrievalDocument(source: source, markdown: "one two three four five six")
        let first = ChatChunker.chunks(document: document, maxCharacters: 13, overlapCharacters: 5)
        let second = ChatChunker.chunks(document: document, maxCharacters: 13, overlapCharacters: 5)
        #expect(first == second)
        #expect(first.map(\.text) == ["one two three", "three four", "four five six"])
        #expect(first.map(\.id) == ["note:00000000-0000-0000-0000-000000000001:0", "note:00000000-0000-0000-0000-000000000001:1", "note:00000000-0000-0000-0000-000000000001:2"])
        #expect(first.allSatisfy { $0.text.count <= 13 })

        let oversized = ChatRetrievalDocument(source: source, markdown: "abcdefghij")
        #expect(ChatChunker.chunks(document: oversized, maxCharacters: 4).map(\.text) == ["abcd", "efgh", "ij"])
    }

    @Test func sourceKeyAndChunkID_includeKindForCrossModelUUIDCollision() {
        let sharedID = source.id
        let project = ChatSourceReference(id: sharedID, kind: .project, title: "Project", detail: nil)
        let note = ChatSourceReference(id: sharedID, kind: .note, title: "Note", detail: nil)
        #expect(project.key != note.key)
        #expect(ChatRetrievalChunk(source: project, index: 0, text: "x").id !=
                ChatRetrievalChunk(source: note, index: 0, text: "x").id)
    }

    @Test func cosineSimilarity_handlesOrthogonalEqualAndInvalidVectors() {
        #expect(ChatVectorMath.cosineSimilarity([1, 0], [1, 0]) == 1)
        #expect(ChatVectorMath.cosineSimilarity([1, 0], [0, 1]) == 0)
        #expect(ChatVectorMath.cosineSimilarity([0, 0], [1, 0]) == nil)
        #expect(ChatVectorMath.cosineSimilarity([1], [1, 2]) == nil)
    }

    @Test func hybridRanker_usesSemanticsAndFallsBackToLexical() {
        let chunks = [
            ChatRetrievalChunk(source: source, index: 0, text: "budget forecast"),
            ChatRetrievalChunk(source: source, index: 1, text: "launch schedule")
        ]
        let embedder = StubEmbedder(vectors: [
            "project timing": [1, 0],
            "budget forecast": [0, 1],
            "launch schedule": [1, 0]
        ])
        let semantic = ChatHybridRanker().rank(query: "project timing", chunks: chunks, embedder: embedder)
        #expect(semantic.first?.chunk.index == 1)

        let lexical = ChatHybridRanker().rank(query: "budget", chunks: chunks, embedder: NilEmbedder())
        #expect(lexical.map(\.chunk.index) == [0])
        #expect(lexical.first?.semanticScore == nil)
    }
}

private struct StubEmbedder: ChatEmbeddingProviding {
    let vectors: [String: [Float]]
    func vector(for text: String) -> [Float]? { vectors[text] }
}

private struct NilEmbedder: ChatEmbeddingProviding {
    func vector(for text: String) -> [Float]? { nil }
}
