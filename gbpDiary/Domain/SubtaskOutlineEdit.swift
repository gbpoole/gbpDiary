import Foundation

/// One row of a subtask outline, reduced to what restructuring needs. Pure, so the rules can be tested
/// away from SwiftData and the view.
struct OutlineRow: Equatable, Identifiable {
    var id: UUID
    var parentID: UUID?
    var sortOrder: Int

    init(id: UUID, parentID: UUID? = nil, sortOrder: Int = 0) {
        self.id = id
        self.parentID = parentID
        self.sortOrder = sortOrder
    }
}

/// The outcome of a depth change: either nothing happens, or the row gets a new parent (`nil` = it
/// becomes a root of the surface's container).
enum Reparent: Equatable {
    case none
    case to(UUID?)
}

// The keyboard restructuring rules for the row-based subtask editor, kept pure because they decide real
// `Task.parent` edges and `sortOrder` values.
//
// **Tab** makes a row a child of its **preceding sibling at the same depth** — classic outline semantics.
// The row's own subtree travels with it implicitly (nothing else is touched). A row that is first among
// its siblings cannot indent.
//
// **Shift-Tab** promotes a row one level, to its grandparent. Each surface supplies the `floorParentID`
// it will not promote past — the task page passes the page's task id, so a direct child can never be
// promoted out of the subtree you are looking at; curation passes `nil`, its roots already being at the
// top. Leaving a subtree stays the explicit "Detach from Parent" action.
//
// Neither operation can create a cycle: a preceding sibling is never a descendant of the row (sibling
// subtrees are disjoint), and a grandparent is already an ancestor. `TaskParenting.wouldCreateCycle`
// remains the guard for the *drag* path, where an arbitrary target can be chosen.
enum SubtaskOutlineEdit {

    /// Siblings of `parentID`, in the order they render (sortOrder, then input order for ties).
    private static func siblings(of parentID: UUID?, in rows: [OutlineRow]) -> [OutlineRow] {
        rows.enumerated()
            .filter { $0.element.parentID == parentID }
            .sorted { l, r in
                l.element.sortOrder == r.element.sortOrder
                    ? l.offset < r.offset
                    : l.element.sortOrder < r.element.sortOrder
            }
            .map(\.element)
    }

    /// Tab: become a child of the preceding sibling. `.none` for an unknown row or the first of its level.
    static func indent(_ id: UUID, in rows: [OutlineRow]) -> Reparent {
        guard let row = rows.first(where: { $0.id == id }) else { return .none }
        let ordered = siblings(of: row.parentID, in: rows)
        guard let position = ordered.firstIndex(where: { $0.id == id }), position > 0 else { return .none }
        return .to(ordered[position - 1].id)
    }

    /// Shift-Tab: promote to the grandparent, unless the row already sits on the surface's floor.
    static func outdent(_ id: UUID, in rows: [OutlineRow], floorParentID: UUID?) -> Reparent {
        guard let row = rows.first(where: { $0.id == id }) else { return .none }
        guard row.parentID != floorParentID else { return .none }
        guard let parentID = row.parentID else { return .none }
        // The parent lives above this surface (shouldn't happen when `floorParentID` is right) — refuse
        // rather than guess at a reparent the caller can't see.
        guard let parent = rows.first(where: { $0.id == parentID }) else { return .none }
        return .to(parent.parentID)
    }

    /// Where a newly added row goes: after everything already at that level (max + 1, not count — a gap
    /// left by a deletion must not collide). Mirrors `BoardPlacement.appendOrder`.
    static func appendSortOrder(parentID: UUID?, in rows: [OutlineRow]) -> Int {
        (rows.filter { $0.parentID == parentID }.map(\.sortOrder).max() ?? -1) + 1
    }

    /// Where a row lands when it is placed immediately **after** `anchorID` among `parentID`'s children —
    /// what Shift-Tab needs, so a promoted row appears next to the parent it just left rather than jumping
    /// to the bottom of its new level.
    ///
    /// The level is renumbered 0…n rather than patched, so no two siblings can collide however gappy the
    /// stored orders were.
    struct Placement: Equatable {
        /// The moved row's new `sortOrder`.
        var order: Int
        /// Siblings whose `sortOrder` must change to make room, by id.
        var shifted: [UUID: Int]
    }

    static func placeAfter(anchorID: UUID, parentID: UUID?, moving movedID: UUID,
                           in rows: [OutlineRow]) -> Placement {
        var ordered = siblings(of: parentID, in: rows).filter { $0.id != movedID }
        guard let anchorIndex = ordered.firstIndex(where: { $0.id == anchorID }) else {
            // Anchor isn't among these siblings — fall back to the end rather than guess.
            return Placement(order: appendSortOrder(parentID: parentID, in: rows), shifted: [:])
        }
        ordered.insert(OutlineRow(id: movedID, parentID: parentID), at: anchorIndex + 1)

        var movedOrder = 0
        var shifted: [UUID: Int] = [:]
        for (order, row) in ordered.enumerated() {
            if row.id == movedID {
                movedOrder = order
            } else if row.sortOrder != order {
                shifted[row.id] = order
            }
        }
        return Placement(order: movedOrder, shifted: shifted)
    }

    /// Every row a deletion would actually take, split into the rows you chose and the descendants that
    /// come with them — `Task.children` cascades, so the second number is the part you can't see.
    struct DeletionScope: Equatable {
        /// The selected rows that aren't themselves inside another selected row.
        var directCount: Int
        /// Everything else swept up by the cascade.
        var descendantCount: Int
        /// All affected ids, deletion roots included.
        var ids: Set<UUID>
        /// The rows to actually hand to `modelContext.delete` — SwiftData cascades the rest.
        var roots: Set<UUID>

        /// Confirm only when the damage exceeds what was selected.
        var needsConfirmation: Bool { descendantCount > 0 }
    }

    static func deletionScope(selected: Set<UUID>, in rows: [OutlineRow]) -> DeletionScope {
        guard !selected.isEmpty else {
            return DeletionScope(directCount: 0, descendantCount: 0, ids: [], roots: [])
        }
        let byID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // A selected row nested inside another selected row isn't a deletion root — it would go anyway.
        func hasSelectedAncestor(_ id: UUID) -> Bool {
            var seen: Set<UUID> = [id]
            var cursor = byID[id]?.parentID
            while let current = cursor, seen.insert(current).inserted {
                if selected.contains(current) { return true }
                cursor = byID[current]?.parentID
            }
            return false
        }
        let roots = selected.filter { byID[$0] != nil && !hasSelectedAncestor($0) }

        var childrenByParent: [UUID: [UUID]] = [:]
        for row in rows {
            guard let parent = row.parentID else { continue }
            childrenByParent[parent, default: []].append(row.id)
        }
        var affected: Set<UUID> = []
        var stack = Array(roots)
        while let next = stack.popLast() {
            guard affected.insert(next).inserted else { continue }   // cycle-safe
            stack.append(contentsOf: childrenByParent[next] ?? [])
        }
        return DeletionScope(directCount: roots.count,
                             descendantCount: affected.count - roots.count,
                             ids: affected,
                             roots: roots)
    }
}
