import Foundation

// A sortable snapshot of a Task for the Tasks table: precomputes urgency and exposes Comparable keys so
// SwiftUI `Table` header clicks (KeyPathComparator<TaskRow>) can sort by any column, including urgency
// (which isn't a stored property). The live `task` is used for rendering + actions.
struct TaskRow: Identifiable {
    let task: Task
    var id: UUID { task.id }

    let urgency: Double
    let summaryKey: String
    let statusRank: Int
    let priorityRank: Int
    let dueKey: Date          // distantFuture when no due date → sorts last ascending
    let projectKey: String
    let assigneeKey: String
    let createdAt: Date

    @MainActor
    init(_ task: Task) {
        self.task = task
        self.urgency = TaskUrgency.score(for: task)
        self.summaryKey = task.summary.lowercased()
        self.statusRank = Self.statusOrder(task.status)
        self.priorityRank = task.priority.rank
        self.dueKey = task.dueAt ?? .distantFuture
        self.projectKey = task.project?.name.lowercased() ?? ""
        self.assigneeKey = task.assignee?.name.lowercased() ?? ""
        self.createdAt = task.createdAt
    }

    private static func statusOrder(_ s: TaskStatus) -> Int {
        switch s {
        case .started:         0
        case .todo:            1
        case .followUpPending: 2
        case .completed:       3
        case .cancelled:       4
        }
    }
}
