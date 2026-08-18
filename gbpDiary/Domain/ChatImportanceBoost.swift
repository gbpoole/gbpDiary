import Foundation

// A mild multiplicative boost applied to a chunk's relevance score from its email importance weight
// (Medium 0.5, High 1.0; Low/other 0 = unchanged). Intentionally small so relevance still dominates —
// it re-orders near-ties, not the whole ranking — and it multiplies, so a zero-relevance chunk stays 0
// (importance never resurrects an irrelevant source).
nonisolated enum ChatImportanceBoost {
    static let coefficient: Double = 0.25   // High → +25%, Medium → +12.5%

    static func adjust(score: Float, importanceWeight: Double, coefficient: Double = coefficient) -> Float {
        guard importanceWeight > 0 else { return score }
        return score * Float(1 + coefficient * importanceWeight)
    }
}
