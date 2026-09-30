import Foundation

// Partitions tasks into the diary task-panel's mutually-exclusive buckets for a reference day.
// `inbox` = untriaged, open, top-level tasks (awaiting Review). The action buckets hold **triaged**
// (`!needsTriage`), open, top-level tasks, each assigned to exactly one bucket by priority:
//   **Board lane** (`planHorizon`) → Overdue → Due today → In-progress (`.started`)
//   → Scheduled (scheduledAt falls on the day) → To Do.
// `todo` is the catch-all so every open task is visible somewhere. Pure/testable; reuses `TaskFlags`.
//
// **The board wins.** A planned task is a decision you have already made, so it appears once — in the lane
// you put it in — and never also under a date-derived heading. Nothing is lost by that: the row's own due
// chip still carries the overdue/due-today warning. Lanes order by `planSortOrder`, the same as the board,
// so the panel and the board read in the same sequence.
enum DayTaskBuckets {
    struct Buckets {
        // The board's three lanes, in urgency order — rendered above the date-derived buckets.
        var today: [Task] = []
        var thisWeek: [Task] = []
        var maybe: [Task] = []
        var overdue: [Task] = []
        var dueToday: [Task] = []
        var inProgress: [Task] = []
        var scheduled: [Task] = []
        var todo: [Task] = []
        var inbox: [Task] = []

        var isEmpty: Bool {
            today.isEmpty && thisWeek.isEmpty && maybe.isEmpty
                && overdue.isEmpty && dueToday.isEmpty && inProgress.isEmpty
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

            // Planned work goes to its lane and nowhere else (see the note above).
            if let horizon = task.planHorizon {
                switch horizon {
                case .today:    b.today.append(task)
                case .thisWeek: b.thisWeek.append(task)
                case .maybe:    b.maybe.append(task)
                }
                continue
            }

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
        b.today = byPlanOrder(b.today)
        b.thisWeek = byPlanOrder(b.thisWeek)
        b.maybe = byPlanOrder(b.maybe)
        return b
    }

    /// Lane order, matching the board. Stable on ties so equal `planSortOrder`s keep their input order.
    private static func byPlanOrder(_ tasks: [Task]) -> [Task] {
        tasks.enumerated()
            .sorted { l, r in
                l.element.planSortOrder == r.element.planSortOrder
                    ? l.offset < r.offset
                    : l.element.planSortOrder < r.element.planSortOrder
            }
            .map(\.element)
    }
}
