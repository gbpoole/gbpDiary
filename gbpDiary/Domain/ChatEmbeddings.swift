import Foundation

#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

nonisolated protocol ChatEmbeddingProviding: Sendable {
    var reuseIdentifier: String { get }
    var isAvailable: Bool { get }
    func vector(for text: String) -> [Float]?
}

nonisolated extension ChatEmbeddingProviding {
    var reuseIdentifier: String { String(reflecting: Self.self) }
    var isAvailable: Bool { true }
}

nonisolated enum ChatVectorMath {
    static func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Float? {
        guard !lhs.isEmpty, lhs.count == rhs.count else { return nil }
        var dot: Float = 0
        var lhsSquared: Float = 0
        var rhsSquared: Float = 0
        for index in lhs.indices {
            dot += lhs[index] * rhs[index]
            lhsSquared += lhs[index] * lhs[index]
            rhsSquared += rhs[index] * rhs[index]
        }
        guard lhsSquared > 0, rhsSquared > 0 else { return nil }
        return dot / (sqrt(lhsSquared) * sqrt(rhsSquared))
    }
}

nonisolated struct NaturalLanguageChatEmbedder: ChatEmbeddingProviding {
    var isAvailable: Bool {
        #if canImport(NaturalLanguage)
        NLEmbedding.sentenceEmbedding(for: .english) != nil
        #else
        false
        #endif
    }

    func vector(for text: String) -> [Float]? {
        #if canImport(NaturalLanguage)
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english),
              let vector = embedding.vector(for: text) else { return nil }
        return vector.map(Float.init)
        #else
        return nil
        #endif
    }
}
