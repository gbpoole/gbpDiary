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

    /// Parked: a follow-up is set and its date has not arrived. Such a task scores zero urgency —
    /// "as done as I can do for now" — but stays visible in every list.
    static func isFollowUpParked(followUpAt: Date?, now: Date = Date()) -> Bool {
        guard let f = followUpAt else { return false }
        return now < f
    }

    /// The follow-up date has arrived: actionable again, and displayed like an overdue task. Nothing
    /// mutates when this flips — it is derived from the clock.
    static func isFollowUpDue(followUpAt: Date?, now: Date = Date()) -> Bool {
        guard let f = followUpAt else { return false }
        return now >= f
    }
}
