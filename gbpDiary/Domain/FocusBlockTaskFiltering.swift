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
}
