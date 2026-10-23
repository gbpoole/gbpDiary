import Foundation

// Pure task-list filter for the "Add Focus Block" task picker: keep only open (active) tasks, optionally
// restricted to a set of selected project ids. An empty selection means "all projects" (no project filter);
// a non-empty selection is OR across the chosen projects, and a task with no project is excluded. Generic
// over the task shape so it's testable without SwiftData.
nonisolated enum FocusBlockTaskFiltering {
    static func filter<T>(_ tasks: [T],
                          isActive: (T) -> Bool,
                          projectID: (T) -> UUID?,
                          activeProjectIDs: Set<UUID>) -> [T] {
        tasks.filter { task in
            guard isActive(task) else { return false }
            guard !activeProjectIDs.isEmpty else { return true }
            guard let pid = projectID(task) else { return false }
            return activeProjectIDs.contains(pid)
        }
    }

    // MARK: - Project filter chips (inside the task picker)
    //
    // A focus block is backed by a TASK and takes its project from that task, so the editor offers no
    // project field — narrowing by project is a filter on the task picker. These two keep the chip id
    // format in one place: the view both builds the ids and reads them back, and two spellings of the
    // same string would silently stop matching.

    static func projectFilterID(_ projectID: UUID) -> String { "project.\(projectID)" }

    /// The single project being filtered to, or nil when the filter is absent or ambiguous. Used to
    /// seed a new task's project: with no filter there is nothing to infer, and with several there is
    /// no reason to prefer one, so the task editor asks instead (it requires a project).
    static func soleProjectID(activeFilterIDs: Set<String>, among projectIDs: [UUID]) -> UUID? {
        guard activeFilterIDs.count == 1, let id = activeFilterIDs.first else { return nil }
        return projectIDs.first { projectFilterID($0) == id }
    }
}
