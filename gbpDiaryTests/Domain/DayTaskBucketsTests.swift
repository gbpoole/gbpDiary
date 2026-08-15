import Foundation
import Testing
@testable import gbpDiary

@MainActor
struct DayTaskBucketsTests {
    private let cal = Calendar.current
    // A fixed reference day at noon so day-boundary math is unambiguous.
    private var day: Date { Date(timeIntervalSinceReferenceDate: 700_000_000) }
    private var dayStart: Date { cal.startOfDay(for: day) }

    // Action buckets require a triaged task.
    private func reviewed(_ summary: String, status: TaskStatus = .todo) -> Task {
        let t = Task(summary: summary, status: status)
        t.markReviewed()
        return t
    }

    @Test func emptyInput_isEmpty() {
        #expect(DayTaskBuckets.partition(allTasks: [], date: day).isEmpty)
    }

    @Test func inbox_isUntriagedTopLevelOpen() {
        let captured = Task(summary: "captured")               // needsTriage == true
        let child = Task(summary: "child"); child.parent = Task(summary: "p")
        let done = Task(summary: "done", status: .completed)
        let reviewedTask = reviewed("reviewed")                // triaged, no due/sched/started → To Do
        let b = DayTaskBuckets.partition(allTasks: [captured, child, done, reviewedTask], date: day)
        #expect(b.inbox.map(\.id) == [captured.id])
        #expect(b.todo.map(\.id) == [reviewedTask.id])
        #expect(b.overdue.isEmpty && b.dueToday.isEmpty && b.inProgress.isEmpty && b.scheduled.isEmpty)
    }

    @Test func actionBuckets_assignByPriority() {
        let overdue = reviewed("overdue"); overdue.dueAt = dayStart.addingTimeInterval(-3 * 86_400)
        let dueToday = reviewed("dueToday"); dueToday.dueAt = dayStart.addingTimeInterval(3_600)
        let started = reviewed("started", status: .started)
        let scheduled = reviewed("scheduled"); scheduled.scheduledAt = dayStart.addingTimeInterval(9 * 3_600)
        let plain = reviewed("plain")   // no due/sched/started → catch-all To Do

        let b = DayTaskBuckets.partition(allTasks: [overdue, dueToday, started, scheduled, plain], date: day)
        #expect(b.overdue.map(\.id) == [overdue.id])
        #expect(b.dueToday.map(\.id) == [dueToday.id])
        #expect(b.inProgress.map(\.id) == [started.id])
        #expect(b.scheduled.map(\.id) == [scheduled.id])
        #expect(b.todo.map(\.id) == [plain.id])
    }

    @Test func mutuallyExclusive_overdueWinsOverStarted() {
        // A started AND overdue task lands only in Overdue (highest priority).
        let t = reviewed("both", status: .started)
        t.dueAt = dayStart.addingTimeInterval(-2 * 86_400)
        let b = DayTaskBuckets.partition(allTasks: [t], date: day)
        #expect(b.overdue.map(\.id) == [t.id])
        #expect(b.inProgress.isEmpty)
    }

    @Test func waitingTasks_excludedFromActionBuckets() {
        let waiting = reviewed("waiting", status: .started)
        waiting.waitUntil = dayStart.addingTimeInterval(5 * 86_400)   // deferred past the day
        let b = DayTaskBuckets.partition(allTasks: [waiting], date: day)
        #expect(b.isEmpty)   // waiting tasks aren't shown anywhere (not even To Do)
    }

    @Test func completedAndSubtasks_excludedEverywhere() {
        let completed = reviewed("done", status: .completed)
        let child = reviewed("child"); child.parent = reviewed("parent")
        child.dueAt = dayStart.addingTimeInterval(-86_400)   // would be overdue if top-level
        let b = DayTaskBuckets.partition(allTasks: [completed, child], date: day)
        #expect(b.isEmpty)
    }
}
