import Foundation

actor ChatRetrievalWorker {
    static let shared = ChatRetrievalWorker()

    func rebuild(snapshot: ChatCorpusSnapshot, indexURL: URL) -> String? {
        let corpus = ChatCorpusProjection.complete(snapshot: snapshot)
        do {
            try ChatSemanticIndex(fileURL: indexURL).rebuild(documents: corpus.documents)
            return nil
        } catch {
            return "The semantic index could not be updated."
        }
    }

    func rebuildAndSearch(snapshot: ChatCorpusSnapshot, indexURL: URL,
                          query: String, limit: Int) -> ChatRetrievalWorkerResult {
        let corpus = ChatCorpusProjection.complete(snapshot: snapshot)
        let chunks = corpus.documents.flatMap { ChatChunker.chunks(document: $0) }
        do {
            let index = ChatSemanticIndex(fileURL: indexURL)
            try index.rebuild(documents: corpus.documents)
            let indexed = index.search(query: query, limit: limit)
            if !indexed.isEmpty { return ChatRetrievalWorkerResult(chunks: indexed, error: nil) }
            return ChatRetrievalWorkerResult(
                chunks: ChatHybridRanker().rank(query: query, chunks: chunks,
                                                embedder: NaturalLanguageChatEmbedder(), limit: limit),
                error: nil
            )
        } catch {
            return ChatRetrievalWorkerResult(
                chunks: ChatHybridRanker().rank(query: query, chunks: chunks,
                                                embedder: NaturalLanguageChatEmbedder(), limit: limit),
                error: "The semantic index could not be updated; using live local search."
            )
        }
    }
}

nonisolated struct ChatRetrievalWorkerResult: Sendable {
    let chunks: [ChatRankedChunk]
    let error: String?
}
