import Foundation

// The planning board's four sections, in display order.
struct BoardBuckets<Item> {
    var inbox: [Item] = []
    var today: [Item] = []
    var thisWeek: [Item] = []
    var maybe: [Item] = []
}

// Pure partition of tasks into the planning board's sections. Rules:
//  • standing tasks and closed (completed/cancelled) tasks are excluded entirely;
//  • a task still needing triage → Inbox (regardless of any stale horizon);
//  • otherwise it lands in the section for its `planHorizon`; a reviewed task with NO horizon is
//    off-board backlog and appears in no section;
//  • each section is ordered by `planSortOrder` ascending (stable within equal orders).
enum BoardPartition {
    static func partition<Item>(_ items: [Item],
                                needsTriage: (Item) -> Bool,
                                isStanding: (Item) -> Bool,
                                isOpen: (Item) -> Bool,
                                horizon: (Item) -> PlanHorizon?,
                                sortOrder: (Item) -> Int) -> BoardBuckets<Item> {
        var buckets = BoardBuckets<Item>()
        for item in items {
            guard !isStanding(item), isOpen(item) else { continue }
            if needsTriage(item) {
                buckets.inbox.append(item)
                continue
            }
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
        buckets.inbox = sorted(buckets.inbox)
        buckets.today = sorted(buckets.today)
        buckets.thisWeek = sorted(buckets.thisWeek)
        buckets.maybe = sorted(buckets.maybe)
        return buckets
    }
}
