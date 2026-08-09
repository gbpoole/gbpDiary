import Foundation

// Taskwarrior-style urgency: a numeric score that ranks tasks so "what's next" floats to the top.
// The scoring is a pure function of primitive inputs (testable); a MainActor adapter builds the inputs
// from a Task. Coefficients mirror Taskwarrior's defaults (tunable here).
struct UrgencyInputs: Equatable {
    var isOpen: Bool = true        // completed/cancelled tasks are never ranked → score 0
    var dueAt: Date?               // the *effective* due date (see TaskUrgency.effectiveDue)
    var priorityWeight: Double    // 0…1 (TaskPriority.weight)
    var ageDays: Double           // days since created
    var isActive: Bool            // started
    var isScheduledNow: Bool      // scheduledAt ≤ now
    var hasTags: Bool
    var hasProject: Bool
    var isBlocked: Bool           // has an incomplete blocker (Stage 3)
    var isBlocking: Bool          // blocks another open task (Stage 3)
    var isWaiting: Bool           // wait-until in the future (Stage 4)
}

enum TaskUrgency {
    // Coefficients (Taskwarrior-inspired).
    static let cDue = 12.0
    static let cPriority = 6.0
    static let cActive = 4.0
    static let cScheduled = 5.0
    static let cAge = 2.0
    static let cTags = 1.0
    static let cProject = 1.0
    static let cBlocked = -5.0
    static let cBlocking = 8.0
    static let cWaiting = -3.0
    static let ageMaxDays = 365.0

    static func score(_ i: UrgencyInputs, now: Date = Date()) -> Double {
        guard i.isOpen else { return 0 }   // done/cancelled tasks aren't ranked
        var u = 0.0
        u += cDue * dueUrgency(i.dueAt, now: now)
        u += cPriority * i.priorityWeight
        if i.isActive { u += cActive }
        if i.isScheduledNow { u += cScheduled }
        u += cAge * min(max(i.ageDays, 0) / ageMaxDays, 1.0)
        if i.hasTags { u += cTags }
        if i.hasProject { u += cProject }
        if i.isBlocked { u += cBlocked }
        if i.isBlocking { u += cBlocking }
        if i.isWaiting { u += cWaiting }
        return u
    }

    /// The date that drives due-urgency: a pending follow-up's date counts like a due date (so a
    /// follow-up surfaces once it comes due), otherwise the task's own due date. Earliest of the two.
    static func effectiveDue(dueAt: Date?, followUpAt: Date?, isFollowUpPending: Bool) -> Date? {
        let follow = isFollowUpPending ? followUpAt : nil
        return [dueAt, follow].compactMap { $0 }.min()
    }

    /// Due-date ramp (0.2 … 1.0): 1.0 once ≥7 days overdue, 0.2 once >14 days out, linear between; 0 if no due.
    static func dueUrgency(_ dueAt: Date?, now: Date = Date()) -> Double {
        guard let due = dueAt else { return 0 }
        let daysOverdue = now.timeIntervalSince(due) / 86400.0   // + = overdue
        if daysOverdue >= 7 { return 1.0 }
        if daysOverdue >= -14 { return (daysOverdue + 14.0) * 0.8 / 21.0 + 0.2 }
        return 0.2
    }
}

@MainActor
extension TaskUrgency {
    /// Builds inputs from a Task and scores it. (Blocked/blocking/waiting are wired in later stages.)
    static func score(for task: Task, now: Date = Date()) -> Double {
        let inputs = UrgencyInputs(
            isOpen: task.isOpen,
            dueAt: effectiveDue(dueAt: task.dueAt, followUpAt: task.followUpAt,
                                isFollowUpPending: task.status == .followUpPending),
            priorityWeight: task.priority.weight,
            ageDays: now.timeIntervalSince(task.createdAt) / 86400.0,
            isActive: task.status == .started,
            isScheduledNow: task.scheduledAt.map { $0 <= now } ?? false,
            hasTags: !task.tags.isEmpty,
            hasProject: task.project != nil,
            isBlocked: task.isBlocked,
            isBlocking: task.isBlocking,
            isWaiting: task.isWaiting
        )
        return score(inputs, now: now)
    }
}
