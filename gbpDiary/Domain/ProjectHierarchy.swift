import Foundation

// One row of a flattened project hierarchy: the item, its depth (0 = root), and whether it matched the
// current filter/search (vs. being shown only as an ancestor for context).
struct HierarchyRow<Item> {
    let item: Item
    let depth: Int
    let isMatch: Bool
}

// Pure parent → child hierarchy flattening for the Projects table. Given the matched set (filter +
// search), it keeps every match plus the full ancestor chain of each match (so parents stay visible for
// context even when they don't match), orders siblings with the caller's comparator, and returns a
// depth-first flattened list with per-row depth and match flag. No SwiftData — unit-testable.
enum ProjectHierarchy {
    static func rows<Item>(all: [Item],
                           id: (Item) -> UUID,
                           parentID: (Item) -> UUID?,
                           matched: Set<UUID>,
                           sortSiblings: ([Item]) -> [Item]) -> [HierarchyRow<Item>] {
        let byID = Dictionary(all.map { (id($0), $0) }, uniquingKeysWith: { first, _ in first })

        // Visible = matches + all transitive ancestors of matches.
        var visible = Set<UUID>()
        for item in all where matched.contains(id(item)) {
            var currentID: UUID? = id(item)
            var guardVisited = Set<UUID>()
            while let cid = currentID, guardVisited.insert(cid).inserted {
                visible.insert(cid)
                currentID = byID[cid].flatMap(parentID)
            }
        }

        // Children of each visible parent; roots have a nil/absent parent.
        var childrenByParent: [UUID: [Item]] = [:]
        var roots: [Item] = []
        for item in all where visible.contains(id(item)) {
            if let pid = parentID(item), byID[pid] != nil {
                childrenByParent[pid, default: []].append(item)
            } else {
                roots.append(item)
            }
        }

        var result: [HierarchyRow<Item>] = []
        var visited = Set<UUID>()

        func emit(_ items: [Item], depth: Int) {
            for item in sortSiblings(items) {
                let itemID = id(item)
                guard visited.insert(itemID).inserted else { continue }   // cycle guard
                result.append(HierarchyRow(item: item, depth: depth, isMatch: matched.contains(itemID)))
                if let kids = childrenByParent[itemID] {
                    emit(kids, depth: depth + 1)
                }
            }
        }
        emit(roots, depth: 0)
        return result
    }
}
