import Foundation

// Keeps a table selection in sync with filtering/search. When a change hides a selected row we drop it
// from the active selection (so the bulk bar's count reflects only visible-selected rows), but stash it
// so that reverting the filter restores it. Generic over the selection id type (UUID for the Tasks row
// snapshot, PersistentIdentifier for @Model-backed tables). Pure so it can be unit-tested.
enum TableSelectionReconcile {
    /// Given the current visible selection, the stashed (selected-but-hidden) set, and the new set of
    /// visible ids, returns the updated `(selection, stashed)`: ids that left the visible set move to
    /// stashed; stashed ids that re-entered the visible set move back into the selection.
    static func reconcile<ID: Hashable>(
        selection: Set<ID>,
        stashed: Set<ID>,
        visible: Set<ID>
    ) -> (selection: Set<ID>, stashed: Set<ID>) {
        let hidden = selection.subtracting(visible)      // selected but no longer visible
        let restored = stashed.intersection(visible)     // previously hidden, now visible again
        let newSelection = selection.intersection(visible).union(restored)
        let newStashed = stashed.subtracting(restored).union(hidden)
        return (newSelection, newStashed)
    }
}
