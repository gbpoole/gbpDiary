import Foundation
import Testing
@testable import gbpDiary

@MainActor
struct TimesheetComputationTests {
    @Test func tasksInRange_requiresCompletedAtAndDuration() {
        let now = FixedDates.reference
        let interval = DateInterval(start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(3600))

        let included = Task(summary: "included", status: .completed)
        included.completedAt = now
        included.duration = Duration(value: 1, unit: .h)

        let noDuration = Task(summary: "no-duration", status: .completed)
        noDuration.completedAt = now

        let noCompletedAt = Task(summary: "no-completed", status: .completed)
        noCompletedAt.duration = Duration(value: 1, unit: .h)

        let result = TimesheetComputation.tasksInRange(allTasks: [included, noDuration, noCompletedAt], interval: interval)
        #expect(result.map(\.id) == [included.id])
    }

    @Test func totalHoursAndProjectHours_sumNormalizedDurations() {
        let projectA = Project(name: "A")
        let projectB = Project(name: "B")

        let t1 = Task(summary: "t1")
        t1.duration = Duration(value: 2, unit: .h)
        t1.project = projectA

        let t2 = Task(summary: "t2")
        t2.duration = Duration(value: 1, unit: .d)
        t2.project = projectA

        let t3 = Task(summary: "t3")
        t3.duration = Duration(value: 1, unit: .h)
        t3.project = projectB

        let tasks = [t1, t2, t3]
        #expect(TimesheetComputation.totalHours(tasks: tasks) == 10.6)
        #expect(TimesheetComputation.hours(for: projectA, tasks: tasks) == 9.6)
    }

    // Reporting periods are CLOSED and whole-day. The old rolling `now − 7d ..< now` both truncated the
    // edge days (dropping a whole day of block capacity, whose date is start-of-day) and made an exported
    // report cover "up to whenever I pressed the button".

    private var gregorianUTC: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return c
    }

    @Test func rangeInterval_thisWeek_isMondayToFridayWholeDays() {
        let cal = gregorianUTC
        let wednesday = cal.date(from: DateComponents(year: 2026, month: 1, day: 7, hour: 14))!
        let interval = TimesheetComputation.rangeInterval(selectedRange: .thisWeek, customStart: wednesday,
                                                         customEnd: wednesday, now: wednesday, calendar: cal)
        #expect(interval.start == cal.date(from: DateComponents(year: 2026, month: 1, day: 5))!)   // Mon
        #expect(interval.end == cal.date(from: DateComponents(year: 2026, month: 1, day: 10))!)    // Sat 00:00
    }

    // Parked on the weekend, "This Week" is the week just worked — weekend work folds back into Friday.
    @Test func rangeInterval_thisWeek_onASaturday_isTheWeekJustWorked() {
        let cal = gregorianUTC
        let saturday = cal.date(from: DateComponents(year: 2026, month: 1, day: 10, hour: 11))!
        let interval = TimesheetComputation.rangeInterval(selectedRange: .thisWeek, customStart: saturday,
                                                         customEnd: saturday, now: saturday, calendar: cal)
        #expect(interval.start == cal.date(from: DateComponents(year: 2026, month: 1, day: 5))!)   // Mon
        #expect(interval.end == cal.date(from: DateComponents(year: 2026, month: 1, day: 10))!)    // Sat 00:00
    }

    @Test func rangeInterval_lastWeek_isThePrecedingMonToFri() {
        let cal = gregorianUTC
        let wednesday = cal.date(from: DateComponents(year: 2026, month: 1, day: 7, hour: 14))!
        let interval = TimesheetComputation.rangeInterval(selectedRange: .lastWeek, customStart: wednesday,
                                                         customEnd: wednesday, now: wednesday, calendar: cal)
        #expect(interval.start == cal.date(from: DateComponents(year: 2025, month: 12, day: 29))!)
        #expect(interval.end == cal.date(from: DateComponents(year: 2026, month: 1, day: 3))!)
    }

    @Test func rangeInterval_last7Days_isSevenWholeDaysEndingToday() {
        let cal = gregorianUTC
        let now = cal.date(from: DateComponents(year: 2026, month: 1, day: 7, hour: 14))!
        let interval = TimesheetComputation.rangeInterval(selectedRange: .last7Days, customStart: now,
                                                         customEnd: now, now: now, calendar: cal)
        #expect(interval.start == cal.date(from: DateComponents(year: 2026, month: 1, day: 1))!)
        #expect(interval.end == cal.date(from: DateComponents(year: 2026, month: 1, day: 8))!)
        #expect(interval.duration == 7 * 24 * 60 * 60)
    }

    @Test func rangeInterval_thisMonth_startsAtTheMonthAndEndsAtEndOfToday() {
        let cal = gregorianUTC
        let now = cal.date(from: DateComponents(year: 2026, month: 3, day: 17, hour: 10))!
        let interval = TimesheetComputation.rangeInterval(selectedRange: .thisMonth, customStart: now,
                                                         customEnd: now, now: now, calendar: cal)
        #expect(interval.start == cal.date(from: DateComponents(year: 2026, month: 3, day: 1))!)
        #expect(interval.end == cal.date(from: DateComponents(year: 2026, month: 3, day: 18))!)   // not `now`
    }

    @Test func rangeInterval_lastMonth_isTheWholePreviousMonth() {
        let cal = gregorianUTC
        let now = cal.date(from: DateComponents(year: 2026, month: 3, day: 17, hour: 10))!
        let interval = TimesheetComputation.rangeInterval(selectedRange: .lastMonth, customStart: now,
                                                         customEnd: now, now: now, calendar: cal)
        #expect(interval.start == cal.date(from: DateComponents(year: 2026, month: 2, day: 1))!)
        #expect(interval.end == cal.date(from: DateComponents(year: 2026, month: 3, day: 1))!)
    }

    @Test func rangeInterval_thisYear_startsAtTheYearAndEndsAtEndOfToday() {
        let cal = gregorianUTC
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 10))!
        let interval = TimesheetComputation.rangeInterval(selectedRange: .thisYear, customStart: now,
                                                         customEnd: now, now: now, calendar: cal)
        #expect(interval.start == cal.date(from: DateComponents(year: 2026, month: 1, day: 1))!)
        #expect(interval.end == cal.date(from: DateComponents(year: 2026, month: 9, day: 5))!)
    }

    // The pickers choose DAYS: the chosen end day is included in full, whatever o'clock the picker holds.
    @Test func rangeInterval_custom_includesBothWholeDays() {
        let cal = gregorianUTC
        let from = cal.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 16))!
        let to = cal.date(from: DateComponents(year: 2026, month: 1, day: 9, hour: 9))!
        let interval = TimesheetComputation.rangeInterval(selectedRange: .custom, customStart: from,
                                                         customEnd: to, now: to, calendar: cal)
        #expect(interval.start == cal.date(from: DateComponents(year: 2026, month: 1, day: 5))!)
        #expect(interval.end == cal.date(from: DateComponents(year: 2026, month: 1, day: 10))!)
    }

    @Test func rangeInterval_custom_toleratesReversedPickers() {
        let cal = gregorianUTC
        let from = cal.date(from: DateComponents(year: 2026, month: 1, day: 9))!
        let to = cal.date(from: DateComponents(year: 2026, month: 1, day: 5))!
        let interval = TimesheetComputation.rangeInterval(selectedRange: .custom, customStart: from,
                                                         customEnd: to, now: from, calendar: cal)
        #expect(interval.start == cal.date(from: DateComponents(year: 2026, month: 1, day: 5))!)
        #expect(interval.end == cal.date(from: DateComponents(year: 2026, month: 1, day: 10))!)
    }

    @Test func rangeInterval_usesCalendarAwareDayLengthAcrossDST() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        // 8 Mar 2026 springs forward: that day is 23h long.
        let springForward = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
        let interval = TimesheetComputation.rangeInterval(selectedRange: .last7Days, customStart: springForward,
                                                         customEnd: springForward, now: springForward,
                                                         calendar: calendar)
        #expect(interval.start == calendar.date(from: DateComponents(year: 2026, month: 3, day: 2))!)
        #expect(interval.end == calendar.date(from: DateComponents(year: 2026, month: 3, day: 9))!)
        #expect(interval.duration == (7 * 24 - 1) * 60 * 60)   // one hour lost to the DST shift
    }

    @Test func workWeek_ofAMondayIsThatWeek() {
        let cal = gregorianUTC
        let monday = cal.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 9))!
        let interval = TimesheetComputation.workWeek(containing: monday, calendar: cal)
        #expect(interval.start == cal.startOfDay(for: monday))
        #expect(interval.end == cal.date(from: DateComponents(year: 2026, month: 1, day: 10))!)
    }

    @Test func tasksInRange_excludesTaskBeforeIntervalStartBoundary() {
        let now = FixedDates.reference
        let interval = DateInterval(start: now.addingTimeInterval(-3600), end: now)

        let beforeStart = Task(summary: "before-start", status: .completed)
        beforeStart.completedAt = now.addingTimeInterval(-3601)
        beforeStart.duration = Duration(value: 1, unit: .h)

        let inside = Task(summary: "inside", status: .completed)
        inside.completedAt = now.addingTimeInterval(-1)
        inside.duration = Duration(value: 1, unit: .h)

        let result = TimesheetComputation.tasksInRange(allTasks: [beforeStart, inside], interval: interval)
        #expect(result.map(\.id) == [inside.id])
    }

    // MARK: - Entry-based (TaskTimeEntry) tests

    @Test func entriesInRange_filtersCorrectly() {
        let now = FixedDates.reference
        let interval = DateInterval(start: now.addingTimeInterval(-3600), end: now)

        let inside = TaskTimeEntry(date: now.addingTimeInterval(-1800), duration: Duration(value: 1, unit: .h))
        let before = TaskTimeEntry(date: now.addingTimeInterval(-7200), duration: Duration(value: 2, unit: .h))
        let after = TaskTimeEntry(date: now.addingTimeInterval(60), duration: Duration(value: 0.5, unit: .h))

        let result = TimesheetComputation.entriesInRange(allEntries: [inside, before, after], interval: interval)
        #expect(result.map(\.id) == [inside.id])
    }

    @Test func totalHours_entries_sumsHours() {
        let e1 = TaskTimeEntry(date: FixedDates.reference, duration: Duration(value: 1.5, unit: .h))
        let e2 = TaskTimeEntry(date: FixedDates.reference, duration: Duration(value: 1, unit: .d))  // 7.6h

        let total = TimesheetComputation.totalHours(entries: [e1, e2])
        #expect(total == 9.1)
    }

    @Test func hours_for_project_entries_sumsMatchingEntries() {
        let projectA = Project(name: "A")
        let projectB = Project(name: "B")

        let taskA = Task(summary: "taskA")
        taskA.project = projectA

        let taskB = Task(summary: "taskB")
        taskB.project = projectB

        let e1 = TaskTimeEntry(date: FixedDates.reference, duration: Duration(value: 2, unit: .h))
        e1.task = taskA
        let e2 = TaskTimeEntry(date: FixedDates.reference, duration: Duration(value: 1, unit: .h))
        e2.task = taskA
        // 5h for projectB so A (3h) ≠ B (5h) — a broken filter returning all entries would fail
        let e3 = TaskTimeEntry(date: FixedDates.reference, duration: Duration(value: 5, unit: .h))
        e3.task = taskB

        let all = [e1, e2, e3]
        #expect(TimesheetComputation.hours(for: projectA, entries: all) == 3.0)
        #expect(TimesheetComputation.hours(for: projectB, entries: all) == 5.0)
    }
}
