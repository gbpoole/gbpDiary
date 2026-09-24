import Foundation

// One rendered row in a board lane: the item, how deep it sits, and whether it is a real member of
// the lane or only there to give a member its place in the tree.
struct BoardRow<Item> {
    let item: Item
    let depth: Int
    /// True for an ancestor shown only for context — it carries no `planHorizon` and is not planned.
    let isContext: Bool
}

// Turns a lane's flat membership into the nested rows the board draws.
//
// The model, decided during design:
//  • Placing a task places **every open task in its subtree**, so a subtree shares one lane.
//  • **Ancestors are context, never members**: adding a subtask directly shows its ancestors so you
//    can see where it belongs, but NOT its siblings, and those ancestors hold no horizon.
//  • Top-level groups order by `planSortOrder` (board order); rows inside a group order by the task
//    tree's own `sortOrder`, so a breakdown keeps the sequence you gave it.
enum BoardHierarchy {

    /// Every task that placing `rootID` should put on the board: the whole subtree, minus anything
    /// closed. A task with no open descendants therefore places just itself.
    static func placementTargets(rootID: UUID,
                                 childrenByParent: [UUID: [UUID]],
                                 isOpen: (UUID) -> Bool) -> Set<UUID> {
        var result: Set<UUID> = []
        var stack = [rootID]
        while let next = stack.popLast() {
            guard result.insert(next).inserted else { continue }   // cycle guard
            stack.append(contentsOf: childrenByParent[next] ?? [])
        }
        return result.filter(isOpen)
    }

    /// Lay a lane's members out as nested rows, pulling in the ancestors needed to place them.
    static func rows<Item>(members: [Item],
                           all: [Item],
                           id: (Item) -> UUID,
                           parentID: (Item) -> UUID?,
                           planSortOrder: (Item) -> Int,
                           treeSortOrder: (Item) -> Int) -> [BoardRow<Item>] {
        guard !members.isEmpty else { return [] }
        let byID = Dictionary(all.map { (id($0), $0) }, uniquingKeysWith: { first, _ in first })
        let memberIDs = Set(members.map(id))

        // Visible = members + the ancestor chain of each (context rows).
        var visible = Set<UUID>()
        for member in members {
            var current: UUID? = id(member)
            var guardVisited = Set<UUID>()
            while let cid = current, guardVisited.insert(cid).inserted {
                visible.insert(cid)
                current = byID[cid].flatMap(parentID)
            }
        }

        var childrenByParent: [UUID: [Item]] = [:]
        var roots: [Item] = []
        for item in all where visible.contains(id(item)) {
            if let pid = parentID(item), visible.contains(pid) {
                childrenByParent[pid, default: []].append(item)
            } else {
                roots.append(item)
            }
        }

        // A context root has no board order of its own, so it takes the earliest of its members'.
        func groupOrder(_ item: Item) -> Int {
            if memberIDs.contains(id(item)) { return planSortOrder(item) }
            var best = Int.max
            var stack = childrenByParent[id(item)] ?? []
            var seen = Set<UUID>()
            while let next = stack.popLast() {
                guard seen.insert(id(next)).inserted else { continue }
                if memberIDs.contains(id(next)) { best = min(best, planSortOrder(next)) }
                stack.append(contentsOf: childrenByParent[id(next)] ?? [])
            }
            return best
        }

        var result: [BoardRow<Item>] = []
        var emitted = Set<UUID>()

        func emit(_ items: [Item], depth: Int, sortedByPlan: Bool) {
            let ordered = sortedByPlan
                ? items.sorted { groupOrder($0) < groupOrder($1) }
                : items.sorted { treeSortOrder($0) < treeSortOrder($1) }
            for item in ordered {
                guard emitted.insert(id(item)).inserted else { continue }   // cycle guard
                result.append(BoardRow(item: item, depth: depth,
                                       isContext: !memberIDs.contains(id(item))))
                emit(childrenByParent[id(item)] ?? [], depth: depth + 1, sortedByPlan: false)
            }
        }
        emit(roots, depth: 0, sortedByPlan: true)
        return result
    }
}
