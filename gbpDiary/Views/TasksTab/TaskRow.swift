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
    let scheduledKey: Date    // distantFuture when unscheduled → sorts last ascending
    let projectKey: String
    let assigneeKey: String
    let createdAt: Date
    let timeSpentHours: Double   // logged entries (or legacy duration) + backed focus-block capacity

    // `blockNet` maps FocusBlock.id → net-remaining hours (from TimeLedgerProjection.blockNet); the Time
    // column reports logged entries + the net of the task's focus blocks (TaskTimeReport).
    @MainActor
    init(_ task: Task, blockNet: [UUID: Double] = [:]) {
        self.task = task
        self.urgency = TaskUrgency.score(for: task)
        self.summaryKey = task.summary.lowercased()
        self.statusRank = Self.statusOrder(task.status)
        self.priorityRank = task.priority.rank
        self.dueKey = task.dueAt ?? .distantFuture
        self.scheduledKey = task.scheduledAt ?? .distantFuture
        self.projectKey = task.project?.name.lowercased() ?? ""
        self.assigneeKey = task.assignee?.name.lowercased() ?? ""
        self.createdAt = task.createdAt
        self.timeSpentHours = TaskTimeReport.totalHours(
            entryHours: task.loggedHoursNormalized,
            hasEntries: !task.timeEntries.isEmpty,
            legacyHours: task.duration?.hoursNormalized,
            blockNets: task.focusBlocks.map { blockNet[$0.id] ?? 0 })
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
