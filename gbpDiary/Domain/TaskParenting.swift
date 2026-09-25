import Foundation

// Guards re-parenting a task in the task tree (making it a subtask of another task).
//
// The trap is a cycle: parenting a task to one of its own descendants detaches that whole branch from
// the tree into a ring, which then makes every tree walk (breakdown, board hierarchy, roll-up) either
// loop or silently lose tasks. Mirrors `TaskDependency.wouldCreateCycle`, which does the same job for
// the "Blocked by" graph.
enum TaskParenting {

    /// Every task in `rootID`'s subtree, including itself. Cycle-safe.
    static func subtree(of rootID: UUID, childrenByParent: [UUID: [UUID]]) -> Set<UUID> {
        var result: Set<UUID> = []
        var stack = [rootID]
        while let next = stack.popLast() {
            guard result.insert(next).inserted else { continue }
            stack.append(contentsOf: childrenByParent[next] ?? [])
        }
        return result
    }

    /// True when making `newParentID` the parent of `taskID` would create a cycle — i.e. the proposed
    /// parent is the task itself, or sits somewhere beneath it.
    static func wouldCreateCycle(taskID: UUID,
                                 newParentID: UUID,
                                 childrenByParent: [UUID: [UUID]]) -> Bool {
        subtree(of: taskID, childrenByParent: childrenByParent).contains(newParentID)
    }
}
