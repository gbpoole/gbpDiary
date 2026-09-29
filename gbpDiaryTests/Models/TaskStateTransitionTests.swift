import Foundation
import Testing
@testable import gbpDiary

@MainActor
struct TaskStateTransitionTests {
    @Test func markCompleted_setsExpectedFields() {
        let task = Task(summary: "a", status: .todo)
        task.cancelledAt = FixedDates.reference  // pre-existing cancelledAt must be preserved

        task.markCompleted()

        #expect(task.status == .completed)
        #expect(task.completedAt != nil)
        #expect(task.cancelledAt == FixedDates.reference)  // not cleared
    }

    @Test func markCompleted_preservesExistingCompletedAt() {
        let task = Task(summary: "a", status: .todo)
        task.completedAt = FixedDates.reference
        task.markCompleted()
        #expect(task.completedAt == FixedDates.reference)
    }

    @Test func markCompleted_preservesExistingCancelledAt() {
        let task = Task(summary: "a", status: .cancelled)
        task.cancelledAt = FixedDates.reference
        task.markCompleted()
        #expect(task.cancelledAt == FixedDates.reference)
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
        task.completedAt = FixedDates.reference  // pre-existing completedAt must be preserved

        task.markCancelled()

        #expect(task.status == .cancelled)
        #expect(task.cancelledAt != nil)
        #expect(task.completedAt == FixedDates.reference)  // not cleared
    }

    @Test func markCancelled_preservesExistingCancelledAt() {
        let task = Task(summary: "a", status: .todo)
        task.cancelledAt = FixedDates.reference
        task.markCancelled()
        #expect(task.cancelledAt == FixedDates.reference)
    }

    @Test func markCancelled_preservesExistingCompletedAt() {
        let task = Task(summary: "a", status: .completed)
        task.completedAt = FixedDates.reference
        task.markCancelled()
        #expect(task.completedAt == FixedDates.reference)
    }

    @Test func cycling_preservesOriginalCompletedAt() {
        let task = Task(summary: "a", status: .completed)
        task.completedAt = FixedDates.reference
        task.setFollowUp(date: FixedDates.dayStart(offsetDays: 1), note: "chasing")
        task.markCancelled()
        task.unmarkCancelled()
        task.status = .started; task.updatedAt = Date()
        task.markCompleted()
        #expect(task.completedAt == FixedDates.reference)
    }

    @Test func unmarkCancelled_reopensTask() {
        let task = Task(summary: "a", status: .cancelled)
        task.cancelledAt = FixedDates.reference

        task.unmarkCancelled()

        #expect(task.status == .todo)
        #expect(task.cancelledAt == nil)
    }

    @Test func markCancelled_clearsFollowUpAt() {
        let task = Task(summary: "a", status: .followUpPending)
        task.followUpAt = FixedDates.dayStart(offsetDays: 1)

        task.markCancelled()

        #expect(task.followUpAt == nil)
    }

    @Test func unmarkCancelled_clearsFollowUpAt() {
        let task = Task(summary: "a", status: .cancelled)
        task.cancelledAt = FixedDates.reference
        task.followUpAt = FixedDates.dayStart(offsetDays: 1)

        task.unmarkCancelled()

        #expect(task.followUpAt == nil)
    }

    @Test func clearFollowUp_noOpWhenNotFollowUpPending() {
        let task = Task(summary: "a", status: .completed)
        task.completedAt = FixedDates.reference

        task.clearFollowUp()

        #expect(task.status == .completed)
        #expect(task.completedAt == FixedDates.reference)
    }

    @Test func setFollowUp_setsPendingStateDateAndRecordsTheNote() {
        let task = Task(summary: "a", status: .completed)
        let due = FixedDates.dayStart(offsetDays: 1)

        task.setFollowUp(date: due, note: "waiting on Sam")

        #expect(task.status == .followUpPending)
        #expect(task.followUpAt == due)
        // History is written when the follow-up is SET — that is the moment you know why.
        #expect(task.followedUpHistory.map(\.date) == [due])
        #expect(task.followedUpHistory.map(\.note) == ["waiting on Sam"])
    }

    /// Setting successive follow-ups builds the list; entries are never rewritten or removed.
    @Test func setFollowUp_appendsToHistory() {
        let task = Task(summary: "a")
        let first = FixedDates.dayStart(offsetDays: 1)
        let second = FixedDates.dayStart(offsetDays: 8)

        task.setFollowUp(date: first, note: "chased")
        task.clearFollowUp()
        task.setFollowUp(date: second, note: "chased again")

        #expect(task.followedUpHistory.map(\.note) == ["chased", "chased again"])
        #expect(task.followedUpHistory.map(\.date) == [first, second])
    }

    /// The pending entry is the LAST one recorded, and only while a follow-up is actually live.
    @Test func pendingFollowUpEntry_isTheLastOneAndOnlyWhilePending() {
        let task = Task(summary: "a")
        #expect(task.pendingFollowUpEntry == nil)

        task.setFollowUp(date: FixedDates.dayStart(offsetDays: 1), note: "first")
        task.setFollowUp(date: FixedDates.dayStart(offsetDays: 8), note: "second")
        #expect(task.pendingFollowUpEntry?.note == "second")

        task.clearFollowUp()                       // no live follow-up any more
        #expect(task.pendingFollowUpEntry == nil)
        #expect(task.followedUpHistory.count == 2, "the record survives")
    }

    /// Correcting the pending entry edits it in place and drags `followUpAt` with it — the two mirror each
    /// other, so they must never drift apart.
    @Test func updateFollowUp_onThePendingEntry_movesFollowUpAt() {
        let task = Task(summary: "a")
        task.setFollowUp(date: FixedDates.dayStart(offsetDays: 1), note: "typo")
        let entry = task.pendingFollowUpEntry!
        let moved = FixedDates.dayStart(offsetDays: 5)

        task.updateFollowUp(entryID: entry.id, date: moved, note: "waiting on Sam")

        #expect(task.followedUpHistory.count == 1, "a correction never appends")
        #expect(task.followUpAt == moved)
        #expect(task.followedUpHistory.first?.note == "waiting on Sam")
        #expect(task.followedUpHistory.first?.id == entry.id, "identity is kept")
    }

    /// Editing an older entry is a correction of the record only — the live follow-up is untouched.
    @Test func updateFollowUp_onAnOlderEntry_leavesFollowUpAtAlone() {
        let task = Task(summary: "a")
        task.setFollowUp(date: FixedDates.dayStart(offsetDays: 1), note: "first")
        let older = task.followedUpHistory[0]
        task.setFollowUp(date: FixedDates.dayStart(offsetDays: 8), note: "second")
        let pendingDate = task.followUpAt

        task.updateFollowUp(entryID: older.id, date: FixedDates.dayStart(offsetDays: -3), note: "fixed")

        #expect(task.followUpAt == pendingDate)
        #expect(task.followedUpHistory.map(\.note) == ["fixed", "second"], "append order is preserved")
    }

    /// Removing the pending entry ENDS the follow-up: the date goes and the task drops to To do, so it can
    /// never be stranded in `.followUpPending` with no date.
    @Test func removeFollowUp_ofThePendingEntry_endsTheFollowUp() {
        let task = Task(summary: "a")
        task.setFollowUp(date: FixedDates.dayStart(offsetDays: 1), note: "waiting")
        let entry = task.pendingFollowUpEntry!

        task.removeFollowUp(entryID: entry.id)

        #expect(task.followedUpHistory.isEmpty)
        #expect(task.followUpAt == nil)
        #expect(task.status == .todo)
    }

    /// Removing an older entry is pure housekeeping — the live follow-up stays exactly as it was.
    @Test func removeFollowUp_ofAnOlderEntry_keepsTheFollowUpRunning() {
        let task = Task(summary: "a")
        task.setFollowUp(date: FixedDates.dayStart(offsetDays: 1), note: "mistake")
        let older = task.followedUpHistory[0]
        let live = FixedDates.dayStart(offsetDays: 8)
        task.setFollowUp(date: live, note: "real")

        task.removeFollowUp(entryID: older.id)

        #expect(task.followedUpHistory.map(\.note) == ["real"])
        #expect(task.followUpAt == live)
        #expect(task.status == .followUpPending)
    }

    /// A follow-up is a DAY: the stored date never carries a time of day, so "today" means today.
    @Test func setFollowUp_storesTheDayNotTheTime() {
        let task = Task(summary: "a")
        let afternoon = FixedDates.dayStart(offsetDays: 2).addingTimeInterval(14 * 3_600)

        task.setFollowUp(date: afternoon, note: "why")

        #expect(task.followUpAt == FixedDates.dayStart(offsetDays: 2))
        #expect(task.followedUpHistory.first?.date == FixedDates.dayStart(offsetDays: 2))
    }

    /// Follow-up implies IN PROGRESS, so ending one must not decide the task is finished. This
    /// reverses the old behaviour, where clearFollowUp() completed the task.
    @Test func clearFollowUp_leavesStatusAlone() {
        let task = Task(summary: "a")
        task.setFollowUp(date: FixedDates.dayStart(offsetDays: 1), note: "waiting")
        #expect(task.status == .followUpPending)

        task.clearFollowUp()

        #expect(task.followUpAt == nil)
        #expect(task.status == .followUpPending, "clearing the date must not complete the task")
        #expect(task.followedUpHistory.count == 1, "history is append-only")
    }

    /// Ending a follow-up is choosing another status — the same path any other task takes — and it leaves
    /// the history alone. (The old `markFollowUpDone()` did this and nothing called it; it was deleted.)
    @Test func completingAFollowUp_clearsTheDateAndKeepsTheHistory() {
        let due = FixedDates.dayStart(offsetDays: 1)
        let task = Task(summary: "a")
        task.setFollowUp(date: due, note: "chased")

        task.followUpAt = nil          // what TaskStatusMenu.setStatus(.completed) does
        task.markCompleted()

        #expect(task.status == .completed)
        #expect(task.followUpAt == nil)
        #expect(task.followedUpHistory.map(\.note) == ["chased"])
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

    @Test func setDuration_completesStartedTask() {
        let task = Task(summary: "a", status: .started)

        task.setDuration(Duration(value: 1, unit: .h))

        #expect(task.status == .completed)
        #expect(task.completedAt != nil)
    }

    @Test func setDuration_doesNotOverwriteExistingCompletedAt() {
        let task = Task(summary: "a", status: .completed)
        task.completedAt = FixedDates.reference
        let dur = Duration(value: 1, unit: .h)

        task.setDuration(dur)

        // Primary job: duration is stored regardless
        #expect(task.duration == dur)
        // Guard: timestamp and status must be unchanged
        #expect(task.completedAt == FixedDates.reference)
        #expect(task.status == .completed)
    }

    @Test func newTask_needsTriageByDefault() {
        #expect(Task(summary: "captured").needsTriage)
    }

    @Test func markReviewed_clearsNeedsTriage() {
        let task = Task(summary: "captured")
        task.markReviewed()
        #expect(!task.needsTriage)
    }

    @Test func markReviewed_noOpWhenAlreadyReviewed() {
        let task = Task(summary: "captured")
        task.markReviewed()
        let stamp = task.updatedAt
        task.markReviewed()   // second call is a no-op (doesn't bump updatedAt)
        #expect(!task.needsTriage)
        #expect(task.updatedAt == stamp)
    }
}
