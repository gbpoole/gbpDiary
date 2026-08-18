import Foundation
import Testing
@testable import gbpDiary

struct ChatImportanceBoostTests {
    @Test func lowWeight_leavesScoreUnchanged() {
        #expect(ChatImportanceBoost.adjust(score: 0.4, importanceWeight: 0) == 0.4)
    }

    @Test func mediumAndHigh_scaleMonotonically() {
        let base: Float = 0.4
        let low = ChatImportanceBoost.adjust(score: base, importanceWeight: 0.0)
        let medium = ChatImportanceBoost.adjust(score: base, importanceWeight: 0.5)
        let high = ChatImportanceBoost.adjust(score: base, importanceWeight: 1.0)
        #expect(low < medium)
        #expect(medium < high)
        // High = base * (1 + 0.25*1.0) = 0.5
        #expect(abs(high - 0.5) < 0.0001)
    }

    @Test func zeroScore_staysZero() {
        // Importance never resurrects an irrelevant (zero-relevance) chunk.
        #expect(ChatImportanceBoost.adjust(score: 0, importanceWeight: 1.0) == 0)
    }

    @Test func mildBoost_doesNotOvertakeAMuchHigherBaseScore() {
        let importantLowRelevance = ChatImportanceBoost.adjust(score: 0.3, importanceWeight: 1.0) // 0.375
        let plainHighRelevance = ChatImportanceBoost.adjust(score: 0.6, importanceWeight: 0.0)    // 0.6
        #expect(importantLowRelevance < plainHighRelevance)
    }
}
