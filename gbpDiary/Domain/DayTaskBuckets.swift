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
        // The "today window" folds the weekend into Monday: on Monday it spans Sat..<Tue, so a task due
        // or scheduled over the weekend counts as due-today/scheduled (not overdue). Other weekdays are a
        // single day. See WeekendPolicy.
        let window = WeekendPolicy.forwardRange(for: date, calendar: calendar)
        var b = Buckets()
        for task in allTasks {
            // Standing tasks are perpetual and stateless: they are logged from the diary's standing
            // strip, not worked through the action buckets, so they never appear here.
            guard task.parent == nil, task.isOpen, !task.isStanding else { continue }
            if task.needsTriage { b.inbox.append(task); continue }
            if TaskFlags.isWaiting(waitUntil: task.waitUntil, now: date) { continue }

            if let due = task.dueAt, due < window.lowerBound {
                b.overdue.append(task)
            } else if let due = task.dueAt, window.contains(due) {
                b.dueToday.append(task)
            } else if task.status == .started {
                b.inProgress.append(task)
            } else if let s = task.scheduledAt, window.contains(s) {
                b.scheduled.append(task)
            } else {
                b.todo.append(task)   // catch-all: any other open, triaged, top-level task
            }
        }
        return b
    }
}
