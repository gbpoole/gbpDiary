import Foundation

// Pure dependency-graph logic (cycle prevention), so the view can guard "Blocked by" edits without
// depending on SwiftData. The graph is passed as id → the ids it depends on.
enum TaskDependency {
    /// True if making `task` depend on `newBlocker` would create a cycle — i.e. `newBlocker` already
    /// (transitively) depends on `task`, or they're the same task.
    static func wouldCreateCycle(taskID: UUID, newBlockerID: UUID, dependsOn: [UUID: [UUID]]) -> Bool {
        if taskID == newBlockerID { return true }
        var stack = [newBlockerID]
        var seen = Set<UUID>()
        while let cur = stack.popLast() {
            if cur == taskID { return true }          // reached the task → adding the edge closes a loop
            guard seen.insert(cur).inserted else { continue }
            stack.append(contentsOf: dependsOn[cur] ?? [])
        }
        return false
    }
}
