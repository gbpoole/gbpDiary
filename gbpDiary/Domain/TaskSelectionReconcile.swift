import Foundation

// Keeps a Tasks-table selection in sync with filtering. When a filter change hides a selected task we
// drop it from the active selection (so the bulk bar's count reflects only visible-selected tasks), but
// stash it so that reverting the filter restores it. Pure so it can be unit-tested.
enum TaskSelectionReconcile {
    /// Given the current visible selection, the stashed (selected-but-hidden) set, and the new set of
    /// visible ids, returns the updated `(selection, stashed)`: ids that left the visible set move to
    /// stashed; stashed ids that re-entered the visible set move back into the selection.
    static func reconcile(
        selection: Set<UUID>,
        stashed: Set<UUID>,
        visible: Set<UUID>
    ) -> (selection: Set<UUID>, stashed: Set<UUID>) {
        let hidden = selection.subtracting(visible)      // selected but no longer visible
        let restored = stashed.intersection(visible)     // previously hidden, now visible again
        let newSelection = selection.intersection(visible).union(restored)
        let newStashed = stashed.subtracting(restored).union(hidden)
        return (newSelection, newStashed)
    }
}
