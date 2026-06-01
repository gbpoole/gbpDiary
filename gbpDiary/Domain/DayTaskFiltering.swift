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

    static func followUpsDueTasks(allTasks: [Task], dayEnd: Date) -> [Task] {
        allTasks.filter {
            guard let fu = $0.followUpAt else { return false }
            return fu < dayEnd && $0.status == .followUpPending
        }
    }

    static func backlogTasks(allTasks: [Task], dayStart: Date) -> [Task] {
        allTasks.filter {
            ($0.status == .todo || $0.status == .started)
                && $0.parent == nil
                && $0.dayRecord == nil     // not already in a diary
                && $0.originMinutes == nil // not in a meeting
                && ($0.scheduledAt == nil || $0.scheduledAt! < dayStart)
        }
    }

    static func completedTodayTasks(allTasks: [Task], dayStart: Date, dayEnd: Date) -> [Task] {
        allTasks.filter {
            guard let c = $0.completedAt else { return false }
            return c >= dayStart && c < dayEnd
        }
    }
}
