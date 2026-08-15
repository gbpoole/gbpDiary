import Foundation
import SwiftData

enum DayTaskFiltering {
    static func dayBounds(for date: Date, calendar: Calendar = .current) -> (dayStart: Date, dayEnd: Date) {
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        return (dayStart, dayEnd)
    }

    // IDs of tasks that already appear in today's diary (via dayRecord ownership or legacy DayEntry).
    static func taskEntryIds(from dayRecord: DayRecord?) -> Set<PersistentIdentifier> {
        let fromTasks = Set((dayRecord?.tasks ?? []).map(\.persistentModelID))
        let fromEntries = Set((dayRecord?.entries ?? []).compactMap { $0.task?.persistentModelID })
        return fromTasks.union(fromEntries)
    }

    static func scheduledTasks(
        allTasks: [Task],
        dayStart: Date,
        dayEnd: Date,
        taskEntryIds: Set<PersistentIdentifier>
    ) -> [Task] {
        allTasks.filter {
            guard let s = $0.scheduledAt else { return false }
            return s >= dayStart && s < dayEnd
                && ($0.status == .todo || $0.status == .started)
                && !taskEntryIds.contains($0.persistentModelID)
        }
    }

    // The task inbox: open, top-level tasks awaiting triage (Review). Enriching a task no longer removes
    // it from the inbox — only `markReviewed()` (clearing `needsTriage`) does.
    static func inboxTasks(allTasks: [Task]) -> [Task] {
        allTasks.filter {
            ($0.status == .todo || $0.status == .started)
                && $0.parent == nil
                && $0.needsTriage
        }
    }
}
