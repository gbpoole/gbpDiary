import Foundation

// The planning board's three lanes, in display order. There is no Inbox lane: tasks reach the board
// from the Tasks table, so untriaged work is revealed there by its filter rather than queued here.
struct BoardBuckets<Item> {
    var today: [Item] = []
    var thisWeek: [Item] = []
    var maybe: [Item] = []
}

// Pure partition of tasks into the planning board's sections. Rules:
//  • closed (completed/cancelled) tasks are excluded entirely;
//  • a task lands in the lane for its `planHorizon`; a task with NO horizon is off-board backlog and
//    appears in no lane. Tasks still needing triage are included — placing one IS the triage act, so
//    it carries a horizon like anything else;
//  • standing tasks ARE included: perpetual work such as "Triage Emails" is legitimately planned into
//    a day, and since it never completes it leaves a lane only by being removed;
//  • each section is ordered by `planSortOrder` ascending (stable within equal orders).
enum BoardPartition {
    static func partition<Item>(_ items: [Item],
                                isOpen: (Item) -> Bool,
                                horizon: (Item) -> PlanHorizon?,
                                sortOrder: (Item) -> Int) -> BoardBuckets<Item> {
        var buckets = BoardBuckets<Item>()
        for item in items {
            guard isOpen(item) else { continue }
            switch horizon(item) {
            case .today:    buckets.today.append(item)
            case .thisWeek: buckets.thisWeek.append(item)
            case .maybe:    buckets.maybe.append(item)
            case nil:       break   // reviewed but unplaced → off-board backlog
            }
        }
        // Stable sort by planSortOrder (ties keep input order via the original index).
        func sorted(_ arr: [Item]) -> [Item] {
            arr.enumerated()
                .sorted { lhs, rhs in
                    let l = sortOrder(lhs.element), r = sortOrder(rhs.element)
                    return l != r ? l < r : lhs.offset < rhs.offset
                }
                .map(\.element)
        }
        buckets.today = sorted(buckets.today)
        buckets.thisWeek = sorted(buckets.thisWeek)
        buckets.maybe = sorted(buckets.maybe)
        return buckets
    }
}
