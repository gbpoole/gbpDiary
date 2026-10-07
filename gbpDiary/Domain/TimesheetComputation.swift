import Foundation

// The Timesheet's reporting periods. Every one is a CLOSED, whole-day interval — a report describes a
// period a third party recognises, never "up to whenever I pressed the button" (the old rolling
// `now − 7d ..< now` also silently dropped the earliest day's block capacity, whose date is start-of-day).
// Week periods are the diary's Mon–Fri work week, since weekend work folds back into Friday.
enum TimesheetRange: String, CaseIterable {
    case thisWeek = "This Week"
    case lastWeek = "Last Week"
    case last7Days = "Last 7 Days"
    case thisMonth = "This Month"
    case lastMonth = "Last Month"
    case thisYear = "This Year"
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
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        // An in-progress period still ends on a day boundary (end of today), never mid-day.
        func clamped(_ periodEnd: Date) -> Date { min(periodEnd, tomorrow) }

        switch selectedRange {
        case .thisWeek:
            return workWeek(containing: now, calendar: calendar)
        case .lastWeek:
            let anchor = calendar.date(byAdding: .day, value: -7,
                                       to: WeekendPolicy.workWeekday(for: now, calendar: calendar)) ?? now
            return workWeek(containing: anchor, calendar: calendar)
        case .last7Days:
            let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
            return DateInterval(start: start, end: tomorrow)
        case .thisMonth:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? today
            let next = calendar.date(byAdding: .month, value: 1, to: start) ?? tomorrow
            return DateInterval(start: start, end: clamped(next))
        case .lastMonth:
            let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? today
            let start = calendar.date(byAdding: .month, value: -1, to: thisMonth) ?? thisMonth
            return DateInterval(start: start, end: thisMonth)
        case .thisYear:
            let start = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? today
            let next = calendar.date(byAdding: .year, value: 1, to: start) ?? tomorrow
            return DateInterval(start: start, end: clamped(next))
        case .custom:
            // The pickers choose DAYS, and the chosen end day is included in full.
            let start = calendar.startOfDay(for: min(customStart, customEnd))
            let endDay = calendar.startOfDay(for: max(customStart, customEnd))
            return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay)
        }
    }

    /// The Mon–Fri work week a date belongs to, as a whole-day half-open interval `[Mon, Sat)`. A weekend
    /// date resolves BACK to the Friday its work folds into, so "This Week" on a Saturday is the week just
    /// worked rather than the one about to start.
    static func workWeek(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        let anchor = WeekendPolicy.workWeekday(for: date, calendar: calendar)
        let days = WeekendPolicy.weekdays(ofWeekContaining: anchor, calendar: calendar)
        guard let first = days.first, let last = days.last,
              let end = calendar.date(byAdding: .day, value: 1, to: last) else {
            let start = calendar.startOfDay(for: anchor)
            return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start) ?? start)
        }
        return DateInterval(start: first, end: end)
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

    // Entry-based computation (TaskTimeEntry).

    static func entriesInRange(
        allEntries: [TaskTimeEntry],
        interval: DateInterval
    ) -> [TaskTimeEntry] {
        allEntries.filter { interval.contains($0.date) }
    }

    static func totalHours(entries: [TaskTimeEntry]) -> Double {
        entries.reduce(0.0) { $0 + $1.duration.hoursNormalized }
    }

    static func hours(for project: Project, entries: [TaskTimeEntry]) -> Double {
        entries
            .filter { $0.task?.project?.id == project.id }
            .reduce(0.0) { $0 + $1.duration.hoursNormalized }
    }
}
