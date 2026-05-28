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
}
