import Foundation
import Testing
@testable import gbpDiary

@MainActor
struct TaskStateTransitionTests {
    @Test func markCompleted_setsExpectedFields() {
        let task = Task(summary: "a", status: .todo)
        task.cancelledAt = FixedDates.reference

        task.markCompleted()

        #expect(task.status == .completed)
        #expect(task.completedAt != nil)
        #expect(task.cancelledAt == nil)
    }

    @Test func unmarkCompleted_reopensTask() {
        let task = Task(summary: "a", status: .completed)
        task.completedAt = FixedDates.reference

        task.unmarkCompleted()

        #expect(task.status == .todo)
        #expect(task.completedAt == nil)
    }

    @Test func markCancelled_setsExpectedFields() {
        let task = Task(summary: "a", status: .completed)
        task.completedAt = FixedDates.reference

        task.markCancelled()

        #expect(task.status == .cancelled)
        #expect(task.cancelledAt != nil)
        #expect(task.completedAt == nil)
    }

    @Test func unmarkCancelled_reopensTask() {
        let task = Task(summary: "a", status: .cancelled)
        task.cancelledAt = FixedDates.reference

        task.unmarkCancelled()

        #expect(task.status == .todo)
        #expect(task.cancelledAt == nil)
    }

    @Test func setFollowUp_setsPendingStateAndDate() {
        let task = Task(summary: "a", status: .completed)
        let due = FixedDates.dayStart(offsetDays: 1)

        task.setFollowUp(date: due)

        #expect(task.status == .followUpPending)
        #expect(task.followUpAt == due)
    }

    @Test func markFollowUpDone_appendsHistoryAndCompletes() {
        let due = FixedDates.dayStart(offsetDays: 1)
        let task = Task(summary: "a", status: .followUpPending)
        task.followUpAt = due

        task.markFollowUpDone()

        #expect(task.status == .completed)
        #expect(task.followUpAt == nil)
        #expect(task.followedUpHistory == [due])
        #expect(task.completedAt != nil)
    }

    @Test func setDuration_completesTodoTaskAndStoresDuration() {
        let task = Task(summary: "a", status: .todo)
        let duration = Duration(value: 2, unit: .h)

        task.setDuration(duration)

        #expect(task.duration == duration)
        #expect(task.status == .completed)
        #expect(task.completedAt != nil)
    }
}
