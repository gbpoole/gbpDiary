import Foundation

// Pure ordering for a curation session: starting from a chosen root project, produce the root followed
// by its ACTIVE subprojects depth-first. Completed subprojects (and their whole subtrees) are pruned —
// you don't curate finished work. Siblings are ordered by the caller's comparator. Cycle-safe.
//
// The root is always included even if completed (you launched the session on it deliberately); only
// *sub*projects are filtered by active status.
enum CurationWalk {
    static func order<Item>(rootID: UUID,
                            all: [Item],
                            id: (Item) -> UUID,
                            parentID: (Item) -> UUID?,
                            isActive: (Item) -> Bool,
                            sortSiblings: ([Item]) -> [Item]) -> [Item] {
        let byID = Dictionary(all.map { (id($0), $0) }, uniquingKeysWith: { first, _ in first })
        guard let root = byID[rootID] else { return [] }

        var childrenByParent: [UUID: [Item]] = [:]
        for item in all {
            if let pid = parentID(item) {
                childrenByParent[pid, default: []].append(item)
            }
        }

        var result: [Item] = []
        var visited = Set<UUID>()

        func emit(_ item: Item) {
            let itemID = id(item)
            guard visited.insert(itemID).inserted else { return }   // cycle guard
            result.append(item)
            let kids = (childrenByParent[itemID] ?? []).filter { isActive($0) }
            for child in sortSiblings(kids) { emit(child) }
        }
        emit(root)
        return result
    }
}
