import Foundation

// Pure save-gate for `TaskEditorSheet`. A task always needs a non-blank summary; callers can additionally
// require a project (focus-block task creation, under the task-only-time rule) and/or an assignee (meeting
// action items). Extracted so the gate is unit-testable without the view.
nonisolated enum TaskEditorValidation {
    static func canSave(summary: String,
                        hasProject: Bool, requireProject: Bool,
                        hasAssignee: Bool, requireAssignee: Bool) -> Bool {
        guard !summary.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if requireProject && !hasProject { return false }
        if requireAssignee && !hasAssignee { return false }
        return true
    }
}
