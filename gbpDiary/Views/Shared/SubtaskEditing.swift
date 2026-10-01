import SwiftUI

/// Opt-in row-editing powers for `TaskSubtreeView`.
///
/// `nil` means the subtree renders exactly as it always has — which is how the diary and meeting surfaces
/// stay untouched until they adopt it. Where it is supplied, Tab/Shift-Tab restructure the real tree
/// through the tested rules in `SubtaskOutlineEdit`, and double-clicking a row opens that task's page.
struct SubtaskEditing {
    /// The `parentID` Shift-Tab will not promote past — the page's own task on a task page, `nil` for a
    /// flat container like curation. Leaving a subtree stays the explicit "Detach from Parent" action.
    var floorParentID: UUID?

    /// Apply a depth change: give `task` this parent. **`nil` means "a root of this container"**, which
    /// each surface resolves its own way — the task page makes it a child of the page's task, curation
    /// makes it a top-level project task. The closure also owns stamping `updatedAt`.
    var setParent: (Task, Task?) -> Void

    /// Double-click: open the task's own page. The caller picks `focusOrOpen` or `openInNewTab` — the
    /// diary and meeting surfaces want a new tab so the day or meeting they were in survives.
    var openTask: (Task) -> Void
}
