import Foundation

enum TimesheetRange: String, CaseIterable {
    case today = "Today"
    case yesterday = "Yesterday"
    case pastWeek = "Past Week"
    case currentMonth = "This Month"
    case currentYear = "This Year"
    case custom = "Custom"
}

enum TimesheetComputation {
    static func rangeInterval(
        selectedRange: TimesheetRange,
        customStart: Date,
        customEnd: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DateInterval {
        switch selectedRange {
        case .today:
            let start = calendar.startOfDay(for: now)
            return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start) ?? start)
        case .yesterday:
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            let start = calendar.startOfDay(for: yesterday)
            return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start) ?? start)
        case .pastWeek:
            return DateInterval(start: calendar.date(byAdding: .day, value: -7, to: now) ?? now, end: now)
        case .currentMonth:
            let comps = calendar.dateComponents([.year, .month], from: now)
            let start = calendar.date(from: comps) ?? now
            return DateInterval(start: start, end: now)
        case .currentYear:
            let comps = calendar.dateComponents([.year], from: now)
            let start = calendar.date(from: comps) ?? now
            return DateInterval(start: start, end: now)
        case .custom:
            return DateInterval(start: customStart, end: customEnd)
        }
    }

    static func tasksInRange(allTasks: [Task], interval: DateInterval) -> [Task] {
        allTasks.filter {
            guard let c = $0.completedAt, let _ = $0.duration else { return false }
            return interval.contains(c)
        }
    }

    static func totalHours(tasks: [Task]) -> Double {
        tasks.compactMap { $0.duration?.hoursNormalized }.reduce(0, +)
    }

    static func hours(for project: Project, tasks: [Task]) -> Double {
        tasks
            .filter { $0.project?.id == project.id }
            .compactMap { $0.duration?.hoursNormalized }
            .reduce(0, +)
    }
}
