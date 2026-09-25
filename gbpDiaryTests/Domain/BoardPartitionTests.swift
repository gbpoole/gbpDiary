import Foundation
import Testing
@testable import gbpDiary

struct BoardPartitionTests {
    private struct T {
        let name: String
        var needsTriage = false
        var isStanding = false
        var isOpen = true
        var horizon: PlanHorizon? = nil
        var order = 0
    }

    private func partition(_ items: [T]) -> BoardBuckets<T> {
        BoardPartition.partition(
            items,
            needsTriage: { $0.needsTriage },
            isStanding: { $0.isStanding },
            isOpen: { $0.isOpen },
            horizon: { $0.horizon },
            sortOrder: { $0.order }
        )
    }

    @Test func inboxIsNeedsTriage_regardlessOfHorizon() {
        let b = partition([
            T(name: "new", needsTriage: true, horizon: .today),   // triage wins over stale horizon
            T(name: "t", horizon: .today),
        ])
        #expect(b.inbox.map(\.name) == ["new"])
        #expect(b.today.map(\.name) == ["t"])
    }

    @Test func horizonsRouteToTheirSections() {
        let b = partition([
            T(name: "t", horizon: .today),
            T(name: "w", horizon: .thisWeek),
            T(name: "m", horizon: .maybe),
        ])
        #expect(b.today.map(\.name) == ["t"])
        #expect(b.thisWeek.map(\.name) == ["w"])
        #expect(b.maybe.map(\.name) == ["m"])
    }

    @Test func reviewedWithNoHorizon_isOffBoard() {
        let b = partition([T(name: "backlog", horizon: nil)])
        #expect(b.inbox.isEmpty && b.today.isEmpty && b.thisWeek.isEmpty && b.maybe.isEmpty)
    }

    @Test func standingAndClosed_areExcluded() {
        let b = partition([
            T(name: "standing", isStanding: true, horizon: .today),
            T(name: "done", isOpen: false, horizon: .today),
            T(name: "keep", horizon: .today),
        ])
        #expect(b.today.map(\.name) == ["keep"])
    }

    @Test func sectionsSortByPlanSortOrder_stableOnTies() {
        let b = partition([
            T(name: "c", horizon: .today, order: 2),
            T(name: "a", horizon: .today, order: 1),
            T(name: "b", horizon: .today, order: 1),   // tie with a → input order preserved
        ])
        #expect(b.today.map(\.name) == ["a", "b", "c"])
    }

    @Test func empty_returnsEmptyBuckets() {
        let b = partition([])
        #expect(b.inbox.isEmpty && b.today.isEmpty && b.thisWeek.isEmpty && b.maybe.isEmpty)
    }
}
