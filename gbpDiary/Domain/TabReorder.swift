import Foundation

// Pure reordering for the workspace tab strip. `move` takes the current order of tab ids, the id being
// dragged, and a target index (a chip's index, or `order.count` to append), and returns the new order.
// Dropping a tab onto another places it immediately before that tab; dropping past the end appends.
// Mirrors the remove-then-insert-with-adjustment used by the diary notes reorder (DayView.reorderNote).
enum TabReorder {
    static func move(_ order: [UUID], id: UUID, toIndex: Int) -> [UUID] {
        guard let from = order.firstIndex(of: id) else { return order }
        var result = order
        result.remove(at: from)
        // Account for the removal shifting indices when the item moves rightwards.
        let adjusted = min(max(0, from < toIndex ? toIndex - 1 : toIndex), result.count)
        result.insert(id, at: adjusted)
        return result
    }
}
