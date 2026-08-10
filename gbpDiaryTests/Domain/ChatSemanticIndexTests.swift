import Foundation
import Testing
@testable import gbpDiary

@Suite("Chat semantic sidecar index")
struct ChatSemanticIndexTests {
    @Test func rebuildReusesUnchangedUpdatesChangedAndDeletesStale() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let embedder = CountingEmbedder()
        let index = ChatSemanticIndex(fileURL: url, embedder: embedder)
        let first = document(id: id(1), text: "alpha launch")
        let stale = document(id: id(2), text: "obsolete budget")

        let initial = try index.rebuild(documents: [stale, first])
        #expect(initial == ChatSemanticIndexReport(added: 2, updated: 0, unchanged: 0, deleted: 0))
        let initialCalls = embedder.calls
        #expect(initialCalls == 2)

        let unchanged = try index.rebuild(documents: [first, stale])
        #expect(unchanged.unchanged == 2)
        #expect(embedder.calls == initialCalls)

        let changed = document(id: id(1), text: "alpha revised launch")
        let update = try index.rebuild(documents: [changed])
        #expect(update == ChatSemanticIndexReport(added: 0, updated: 1, unchanged: 0, deleted: 1))
        #expect(index.load()?.sources.map(\.sourceKey) == [changed.id])
        #expect(index.load()?.formatVersion == ChatSemanticIndex.formatVersion)
        #expect(index.load()?.projectionVersion == ChatCorpusBuilder.projectionVersion)
    }

    @Test func crossModelUUIDCollision_indexesBothSources() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let sharedID = id(9)
        let note = document(id: sharedID, kind: .note, text: "note knowledge")
        let project = document(id: sharedID, kind: .project, text: "project knowledge")
        let index = ChatSemanticIndex(fileURL: url, embedder: NilIndexEmbedder())
        let report = try index.rebuild(documents: [note, project])
        #expect(report.added == 2)
        #expect(Set(index.load()?.sources.map(\.sourceKey) ?? []) == Set([note.id, project.id]))
    }

    @Test func reuseRebuildsPreviouslyEmptyBudgetSourceWhenBudgetIncreases() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var emptyBudget = ChatSemanticIndex(fileURL: url, embedder: NilIndexEmbedder())
        emptyBudget.maximumTotalChunks = 0
        try emptyBudget.rebuild(documents: [document(id: id(10), text: "alpha")])
        #expect(emptyBudget.load()?.sources.first?.chunks.isEmpty == true)

        let availableBudget = ChatSemanticIndex(fileURL: url, embedder: NilIndexEmbedder())
        let report = try availableBudget.rebuild(documents: [document(id: id(10), text: "alpha")])
        #expect(report.updated == 1)
        #expect(availableBudget.load()?.sources.first?.chunks.isEmpty == false)
    }

    @Test func reuseIncludesChunkBudgetConfiguration() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var oneChunk = ChatSemanticIndex(fileURL: url, embedder: NilIndexEmbedder())
        oneChunk.maximumChunksPerSource = 1
        let item = document(id: id(12), text: String(repeating: "alpha beta gamma ", count: 200))
        try oneChunk.rebuild(documents: [item])
        #expect(oneChunk.load()?.sources.first?.chunks.count == 1)

        var twoChunks = ChatSemanticIndex(fileURL: url, embedder: NilIndexEmbedder())
        twoChunks.maximumChunksPerSource = 2
        let report = try twoChunks.rebuild(documents: [item])
        #expect(report.updated == 1)
        #expect(twoChunks.load()?.sources.first?.chunks.count == 2)
    }

    @Test func reuseRebuildsNilVectorsWhenSameProviderBecomesAvailable() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let embedder = AvailabilityEmbedder()
        let index = ChatSemanticIndex(fileURL: url, embedder: embedder)
        try index.rebuild(documents: [document(id: id(11), text: "alpha")])
        #expect(index.load()?.sources.first?.embeddingsComplete == false)

        embedder.available = true
        let report = try index.rebuild(documents: [document(id: id(11), text: "alpha")])
        #expect(report.updated == 1)
        #expect(index.load()?.sources.first?.embeddingsComplete == true)
        #expect(index.load()?.sources.first?.vectors.first! == [1, 0])
    }

    @Test func searchUsesStoredVectorsAndFallsBackToLexical() throws {
        let semanticURL = temporaryURL()
        defer { try? FileManager.default.removeItem(at: semanticURL.deletingLastPathComponent()) }
        let vectors = MappingEmbedder(values: [
            "project timing": [1, 0], "budget forecast": [0, 1], "launch schedule": [1, 0]
        ])
        let semantic = ChatSemanticIndex(fileURL: semanticURL, embedder: vectors)
        try semantic.rebuild(documents: [document(id: id(3), text: "budget forecast"),
                                         document(id: id(4), text: "launch schedule")])
        #expect(semantic.search(query: "project timing").first?.chunk.source.id == id(4))

        let lexicalURL = temporaryURL()
        defer { try? FileManager.default.removeItem(at: lexicalURL.deletingLastPathComponent()) }
        let lexical = ChatSemanticIndex(fileURL: lexicalURL, embedder: NilIndexEmbedder())
        try lexical.rebuild(documents: [document(id: id(5), text: "unique telescope")])
        #expect(lexical.search(query: "telescope").first?.chunk.source.id == id(5))
    }

    @Test func corruptOrWrongVersionIndexIsIgnored() throws {
        let url = temporaryURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        let index = ChatSemanticIndex(fileURL: url, embedder: NilIndexEmbedder())
        #expect(index.load() == nil)
        #expect(index.search(query: "anything").isEmpty)
    }

    private func document(id: UUID, kind: ChatSourceKind = .note, text: String) -> ChatRetrievalDocument {
        ChatRetrievalDocument(source: ChatSourceReference(id: id, kind: kind, title: text, detail: nil),
                              markdown: text)
    }

    private func id(_ suffix: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, suffix))
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("index.json")
    }
}

private final class CountingEmbedder: ChatEmbeddingProviding, @unchecked Sendable {
    var calls = 0
    func vector(for text: String) -> [Float]? {
        calls += 1
        return [1, 0]
    }
}

private struct MappingEmbedder: ChatEmbeddingProviding {
    let values: [String: [Float]]
    func vector(for text: String) -> [Float]? { values[text] }
}

private struct NilIndexEmbedder: ChatEmbeddingProviding {
    var isAvailable: Bool { false }
    func vector(for text: String) -> [Float]? { nil }
}

private final class AvailabilityEmbedder: ChatEmbeddingProviding, @unchecked Sendable {
    var available = false
    var reuseIdentifier: String { "availability-test" }
    var isAvailable: Bool { available }
    func vector(for text: String) -> [Float]? { available ? [1, 0] : nil }
}
