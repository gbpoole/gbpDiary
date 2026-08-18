import Foundation
import Testing
@testable import gbpDiary

struct ChatScopedRankingTests {
    private let cal = Calendar(identifier: .gregorian)
    private func d(_ day: Int) -> Date { cal.date(from: DateComponents(year: 2024, month: 6, day: day))! }

    private func ranked(_ kind: ChatSourceKind, _ projects: [String], _ date: Date?, score: Float,
                        importanceWeight: Double = 0) -> ChatRankedChunk {
        let src = ChatSourceReference(id: UUID(), kind: kind, title: "t", detail: nil)
        let chunk = ChatRetrievalChunk(source: src, index: 0, text: "text", projectNames: projects,
                                       sortDate: date, importanceWeight: importanceWeight)
        return ChatRankedChunk(chunk: chunk, score: score, lexicalScore: score, semanticScore: nil)
    }

    @Test func noScope_returnsUnchanged() {
        let input = [ranked(.email, ["nodes - 2026b"], d(10), score: 0.5), ranked(.meeting, [], nil, score: 0.4)]
        #expect(ChatScopedRanking.apply(input, scope: ChatQueryScope()) == input)
    }

    @Test func filtersByKindAndProject() {
        let mine = ranked(.email, ["nodes - 2026b"], d(10), score: 0.5)
        let otherProject = ranked(.email, ["other"], d(11), score: 0.9)
        let meeting = ranked(.meeting, ["nodes - 2026b"], d(12), score: 0.9)
        var scope = ChatQueryScope(); scope.kinds = [.email]; scope.projectName = "NODES - 2026B"
        let out = ChatScopedRanking.apply([mine, otherProject, meeting], scope: scope)
        #expect(out.map(\.chunk.id) == [mine.chunk.id])
    }

    @Test func intervalOrdersRecentFirstAndDropsOutOfWindow() {
        let inA = ranked(.email, ["nodes - 2026b"], d(10), score: 0.3)
        let inB = ranked(.email, ["nodes - 2026b"], d(14), score: 0.3)
        let outside = ranked(.email, ["nodes - 2026b"], d(1), score: 0.9)   // before the window
        var scope = ChatQueryScope(); scope.kinds = [.email]; scope.projectName = "NODES - 2026B"
        scope.interval = d(8)..<d(20)
        let out = ChatScopedRanking.apply([inA, outside, inB], scope: scope)
        #expect(out.map(\.chunk.id) == [inB.chunk.id, inA.chunk.id])   // recent first, outside dropped
    }

    @Test func emptyFilter_fallsBackToUnscoped() {
        let input = [ranked(.email, ["other"], d(10), score: 0.5)]
        var scope = ChatQueryScope(); scope.projectName = "NODES - 2026B"   // matches nothing
        #expect(ChatScopedRanking.apply(input, scope: scope) == input)
    }

    @Test func intervalWithNothingInWindow_returnsEmptyNotOutOfWindow() {
        // "last week" must never surface a February meeting: an explicit interval is a hard bound with no fallback.
        let outOfWindow = ranked(.meeting, ["nodes - 2026b"], d(1), score: 0.9)
        var scope = ChatQueryScope(); scope.interval = d(8)..<d(20)
        #expect(ChatScopedRanking.apply([outOfWindow], scope: scope).isEmpty)
    }

    @Test func intervalDropsOutOfWindow_evenWhenProjectFallbackApplies() {
        // Project link missing → kind/project fallback keeps the chunk, but the interval still drops it.
        let febOtherProject = ranked(.meeting, ["other"], d(1), score: 0.9)
        var scope = ChatQueryScope(); scope.projectName = "NODES - 2026B"; scope.interval = d(8)..<d(20)
        #expect(ChatScopedRanking.apply([febOtherProject], scope: scope).isEmpty)
    }

    @Test func interval_sameDate_importanceBreaksTie() {
        // Equal sortDate → the more-important (higher weight) email leads, despite a lower base score.
        let important = ranked(.email, ["nodes - 2026b"], d(10), score: 0.3, importanceWeight: 1.0)
        let plain = ranked(.email, ["nodes - 2026b"], d(10), score: 0.5, importanceWeight: 0.0)
        var scope = ChatQueryScope(); scope.kinds = [.email]; scope.interval = d(8)..<d(20)
        let out = ChatScopedRanking.apply([plain, important], scope: scope)
        #expect(out.map(\.chunk.id) == [important.chunk.id, plain.chunk.id])
    }
}
