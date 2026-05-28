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

    @Test func rangeInterval_today_startsAtDayBoundary() {
        let now = FixedDates.atHour(10)
        let interval = TimesheetComputation.rangeInterval(
            selectedRange: .today,
            customStart: now,
            customEnd: now,
            now: now
        )

        #expect(interval.start == Calendar.current.startOfDay(for: now))
        #expect(interval.end > interval.start)
    }

    @Test func rangeInterval_yesterday_coversPreviousDayOnly() {
        let now = FixedDates.atHour(10)
        let interval = TimesheetComputation.rangeInterval(
            selectedRange: .yesterday,
            customStart: now,
            customEnd: now,
            now: now
        )

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        let expectedStart = Calendar.current.startOfDay(for: yesterday)
        let expectedEnd = Calendar.current.date(byAdding: .day, value: 1, to: expectedStart) ?? expectedStart
        #expect(interval.start == expectedStart)
        #expect(interval.end == expectedEnd)
    }

    @Test func rangeInterval_custom_usesProvidedBounds() {
        let start = FixedDates.reference.addingTimeInterval(-7200)
        let end = FixedDates.reference.addingTimeInterval(1800)
        let interval = TimesheetComputation.rangeInterval(
            selectedRange: .custom,
            customStart: start,
            customEnd: end,
            now: FixedDates.reference
        )

        #expect(interval.start == start)
        #expect(interval.end == end)
    }

    @Test func rangeInterval_pastWeek_spansSevenDaysToNow() {
        let now = FixedDates.atHour(10)
        let interval = TimesheetComputation.rangeInterval(
            selectedRange: .pastWeek,
            customStart: now,
            customEnd: now,
            now: now
        )

        #expect(interval.end == now)
        #expect(interval.start == Calendar.current.date(byAdding: .day, value: -7, to: now))
    }

    @Test func rangeInterval_currentMonth_startsAtMonthBoundary() {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 3
        comps.day = 17
        comps.hour = 10
        let now = Calendar.current.date(from: comps) ?? FixedDates.reference

        let interval = TimesheetComputation.rangeInterval(
            selectedRange: .currentMonth,
            customStart: now,
            customEnd: now,
            now: now
        )

        let expectedStart = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: now))
        #expect(interval.start == expectedStart)
        #expect(interval.end == now)
    }

    @Test func rangeInterval_currentYear_startsAtYearBoundary() {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 9
        comps.day = 4
        comps.hour = 10
        let now = Calendar.current.date(from: comps) ?? FixedDates.reference

        let interval = TimesheetComputation.rangeInterval(
            selectedRange: .currentYear,
            customStart: now,
            customEnd: now,
            now: now
        )

        let expectedStart = Calendar.current.date(from: Calendar.current.dateComponents([.year], from: now))
        #expect(interval.start == expectedStart)
        #expect(interval.end == now)
    }

    @Test func rangeInterval_pastWeek_crossesYearBoundary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let now = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 10)) ?? FixedDates.reference
        let interval = TimesheetComputation.rangeInterval(
            selectedRange: .pastWeek,
            customStart: now,
            customEnd: now,
            now: now,
            calendar: calendar
        )

        let expectedStart = calendar.date(byAdding: .day, value: -7, to: now)
        #expect(interval.start == expectedStart)
        #expect(interval.end == now)
    }

    @Test func rangeInterval_today_usesCalendarAwareDayLengthAcrossDST() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current

        let springForwardDay = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12)) ?? FixedDates.reference
        let interval = TimesheetComputation.rangeInterval(
            selectedRange: .today,
            customStart: springForwardDay,
            customEnd: springForwardDay,
            now: springForwardDay,
            calendar: calendar
        )

        let expectedStart = calendar.startOfDay(for: springForwardDay)
        let expectedEnd = calendar.date(byAdding: .day, value: 1, to: expectedStart)
        #expect(interval.start == expectedStart)
        #expect(interval.end == expectedEnd)
        #expect(interval.duration == 23 * 60 * 60)
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
}
