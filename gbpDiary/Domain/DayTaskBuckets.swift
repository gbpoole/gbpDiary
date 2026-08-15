import Foundation

// Partitions tasks into the diary task-panel's mutually-exclusive buckets for a reference day.
// `inbox` = untriaged, open, top-level tasks (awaiting Review). The action buckets hold **triaged**
// (`!needsTriage`), open, top-level, non-waiting tasks, each assigned to exactly one bucket by priority:
//   Overdue → Due today → In-progress (`.started`) → Scheduled (scheduledAt falls on the day) → To Do.
// `todo` is the catch-all so every open task is visible somewhere. Pure/testable; reuses `TaskFlags`.
enum DayTaskBuckets {
    struct Buckets {
        var overdue: [Task] = []
        var dueToday: [Task] = []
        var inProgress: [Task] = []
        var scheduled: [Task] = []
        var todo: [Task] = []
        var inbox: [Task] = []

        var isEmpty: Bool {
            overdue.isEmpty && dueToday.isEmpty && inProgress.isEmpty
                && scheduled.isEmpty && todo.isEmpty && inbox.isEmpty
        }
    }

    static func partition(allTasks: [Task], date: Date = Date(),
                          calendar: Calendar = .current) -> Buckets {
        let (dayStart, dayEnd) = DayTaskFiltering.dayBounds(for: date, calendar: calendar)
        var b = Buckets()
        for task in allTasks {
            guard task.parent == nil, task.isOpen else { continue }
            if task.needsTriage { b.inbox.append(task); continue }
            if TaskFlags.isWaiting(waitUntil: task.waitUntil, now: date) { continue }

            if TaskFlags.isOverdue(dueAt: task.dueAt, isOpen: true, now: date, calendar: calendar) {
                b.overdue.append(task)
            } else if TaskFlags.isDueToday(dueAt: task.dueAt, now: date, calendar: calendar) {
                b.dueToday.append(task)
            } else if task.status == .started {
                b.inProgress.append(task)
            } else if let s = task.scheduledAt, s >= dayStart, s < dayEnd {
                b.scheduled.append(task)
            } else {
                b.todo.append(task)   // catch-all: any other open, triaged, top-level task
            }
        }
        return b
    }
}
