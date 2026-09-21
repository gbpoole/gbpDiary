import Foundation

// Pure subtree time roll-up: a parent task's *reported* time = its own logged hours plus the sum of all
// its descendants' own logged hours. This is a reporting aggregation over the task tree only — it does
// NOT change canonical attribution (each activity still counts once to its own task/project in
// TimeLedger). "Own hours" for a node is whatever the caller computed via TaskTimeReport.totalHours.
// Cycle-safe (a task is never counted twice).
enum TaskTimeRollup {
    /// Total hours for the subtree rooted at `rootID`: own hours + all descendants' own hours.
    static func subtreeHours(rootID: UUID,
                             ownHours: [UUID: Double],
                             childrenByParent: [UUID: [UUID]]) -> Double {
        var visited = Set<UUID>()
        func walk(_ id: UUID) -> Double {
            guard visited.insert(id).inserted else { return 0 }   // cycle / re-entry guard
            var total = ownHours[id] ?? 0
            for child in childrenByParent[id] ?? [] {
                total += walk(child)
            }
            return total
        }
        return walk(rootID)
    }
}
