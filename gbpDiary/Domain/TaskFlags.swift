import Foundation

// Pure, testable "virtual tag" predicates for tasks (Taskwarrior-style +OVERDUE / +DUE.TODAY), computed
// from a due date at day granularity. Kept separate from the @Model so it's unit-testable.
enum TaskFlags {
    /// Open task whose due date is before the start of today.
    static func isOverdue(dueAt: Date?, isOpen: Bool, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard isOpen, let due = dueAt else { return false }
        return due < calendar.startOfDay(for: now)
    }

    /// Due date falls on today (regardless of completion).
    static func isDueToday(dueAt: Date?, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let due = dueAt else { return false }
        return calendar.isDate(due, inSameDayAs: now)
    }
}
