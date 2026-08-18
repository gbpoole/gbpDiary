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

    /// The fast query path: search the **already-built** index (only the query is embedded — no
    /// re-projection, attachment extraction, chunking, or re-embedding of the corpus, and no snapshot).
    /// `ChatIndexDriver` keeps the index fresh in the background; the caller falls back to a full rebuild
    /// only when this returns empty (e.g. first launch before the driver has run).
    func searchOnly(indexURL: URL, query: String, limit: Int) -> ChatRetrievalWorkerResult {
        ChatRetrievalWorkerResult(chunks: ChatSemanticIndex(fileURL: indexURL).search(query: query, limit: limit),
                                  error: nil)
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
