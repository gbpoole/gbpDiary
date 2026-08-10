import Foundation

nonisolated struct ChatRankedChunk: Equatable, Sendable {
    let chunk: ChatRetrievalChunk
    let score: Float
    let lexicalScore: Float
    let semanticScore: Float?
}

nonisolated struct ChatIndexedChunk: Equatable, Sendable {
    let chunk: ChatRetrievalChunk
    let vector: [Float]?
}

nonisolated struct ChatHybridRanker {
    var lexicalWeight: Float = 0.45
    var semanticWeight: Float = 0.55

    func rank(query: String, chunks: [ChatRetrievalChunk], embedder: (any ChatEmbeddingProviding)? = nil,
              limit: Int = 8) -> [ChatRankedChunk] {
        let queryTerms = Self.terms(in: query)
        let queryVector = embedder?.vector(for: query)
        return chunks.map { chunk in
            let lexical = Self.lexicalScore(queryTerms: queryTerms, text: chunk.text)
            let semantic = queryVector.flatMap { queryVector in
                embedder?.vector(for: chunk.text).flatMap { ChatVectorMath.cosineSimilarity(queryVector, $0) }
            }
            let score: Float
            if let semantic {
                let clampedSemantic = max(0, min(1, semantic))
                let totalWeight = max(lexicalWeight + semanticWeight, .leastNonzeroMagnitude)
                score = (lexical * lexicalWeight + clampedSemantic * semanticWeight) / totalWeight
            } else {
                score = lexical
            }
            return ChatRankedChunk(chunk: chunk, score: score, lexicalScore: lexical, semanticScore: semantic)
        }
        .filter { $0.score > 0 }
        .sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.chunk.id < $1.chunk.id
        }
        .prefix(max(0, limit))
        .map { $0 }
    }

    func rank(query: String, indexedChunks: [ChatIndexedChunk], queryVector: [Float]?,
              limit: Int = 8) -> [ChatRankedChunk] {
        let queryTerms = Self.terms(in: query)
        return indexedChunks.map { indexed in
            let lexical = Self.lexicalScore(queryTerms: queryTerms, text: indexed.chunk.text)
            let semantic = queryVector.flatMap { query in
                indexed.vector.flatMap { ChatVectorMath.cosineSimilarity(query, $0) }
            }
            let score = combinedScore(lexical: lexical, semantic: semantic)
            return ChatRankedChunk(chunk: indexed.chunk, score: score,
                                   lexicalScore: lexical, semanticScore: semantic)
        }
        .filter { $0.score > 0 }
        .sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.chunk.id < $1.chunk.id
        }
        .prefix(max(0, limit)).map { $0 }
    }

    private func combinedScore(lexical: Float, semantic: Float?) -> Float {
        guard let semantic else { return lexical }
        let totalWeight = max(lexicalWeight + semanticWeight, .leastNonzeroMagnitude)
        return (lexical * lexicalWeight + max(0, min(1, semantic)) * semanticWeight) / totalWeight
    }

    private static func terms(in text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private static func lexicalScore(queryTerms: [String], text: String) -> Float {
        let uniqueQuery = Set(queryTerms)
        guard !uniqueQuery.isEmpty else { return 0 }
        let textTerms = Set(terms(in: text))
        let matches = uniqueQuery.intersection(textTerms).count
        return Float(matches) / Float(uniqueQuery.count)
    }
}
