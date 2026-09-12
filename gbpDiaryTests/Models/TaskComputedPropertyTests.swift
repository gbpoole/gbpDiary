import Foundation
import Testing
@testable import gbpDiary

@MainActor
struct TaskComputedPropertyTests {

    // MARK: - loggedHoursNormalized

    @Test func loggedHoursNormalized_sumsAllTimeEntries() {
        let task = Task(summary: "t")
        let e1 = TaskTimeEntry(date: FixedDates.reference, duration: Duration(value: 1, unit: .h))
        let e2 = TaskTimeEntry(date: FixedDates.reference, duration: Duration(value: 0.5, unit: .h))
        task.timeEntries = [e1, e2]
        #expect(task.loggedHoursNormalized == 1.5)
    }

    @Test func loggedHoursNormalized_emptyEntries_returnsZero() {
        let task = Task(summary: "t")
        #expect(task.loggedHoursNormalized == 0)
    }


    // MARK: - loggedDuration

    @Test func loggedDuration_returnsNilWhenNoEntries() {
        let task = Task(summary: "t")
        #expect(task.loggedDuration == nil)
    }

    @Test func loggedDuration_returnsNonNilWithSummedHours() {
        let task = Task(summary: "t")
        let e1 = TaskTimeEntry(date: FixedDates.reference, duration: Duration(value: 1, unit: .h))
        let e2 = TaskTimeEntry(date: FixedDates.reference, duration: Duration(value: 1, unit: .d))
        task.timeEntries = [e1, e2]
        // 1h + 7.6h = 8.6h
        #expect(task.loggedDuration?.hoursNormalized == 8.6)
    }

    // MARK: - needsChevron

    @Test func needsChevron_falseWhenNoChildrenOrNotes() {
        let task = Task(summary: "t")
        #expect(!task.needsChevron)
    }

    @Test func needsChevron_trueWhenHasChildren() {
        let parent = Task(summary: "parent")
        parent.children = [Task(summary: "child")]
        #expect(parent.needsChevron)
    }

    @Test func needsChevron_trueWhenHasNonEmptyNotes() {
        let task = Task(summary: "t")
        task.notes = "some notes"
        #expect(task.needsChevron)
    }

    @Test func needsChevron_falseWhenNotesIsEmptyString() {
        let task = Task(summary: "t")
        task.notes = ""
        #expect(!task.needsChevron)
    }

    // MARK: - isOpen / email hasOpenTask

    @Test func isOpen_trueUntilCompletedOrCancelled() {
        let task = Task(summary: "t")
        #expect(task.isOpen)                       // todo
        task.status = .started;         #expect(task.isOpen)
        task.status = .followUpPending; #expect(task.isOpen)
        task.status = .completed;       #expect(!task.isOpen)
        task.status = .cancelled;       #expect(!task.isOpen)
    }

    @Test func email_hasOpenTask_reflectsLinkedTaskStatuses() {
        let email = EmailMessage(messageId: "<m>", account: "a", mailbox: "INBOX", direction: .inbox,
                                 fromAddress: "x@y.com", fromName: nil, subject: "s", date: .now)
        #expect(!email.hasTasks)
        let task = Task(summary: "do")
        task.originEmail = email
        #expect(email.hasTasks)
        #expect(email.hasOpenTask)
        task.status = .completed
        #expect(!email.hasOpenTask)
    }

    @Test func email_isSummarizing_trueOnlyWhilePending() {
        let email = EmailMessage(messageId: "<m>", account: "a", mailbox: "Sent", direction: .sent,
                                 fromAddress: "x@y.com", fromName: nil, subject: "s", date: .now)
        #expect(email.isSummarizing)   // default state is pending
        email.summaryState = EmailSummaryState.done.rawValue
        #expect(!email.isSummarizing)
        email.summaryState = EmailSummaryState.failed.rawValue
        #expect(!email.isSummarizing)
        email.summaryState = EmailSummaryState.unavailable.rawValue
        #expect(!email.isSummarizing)
    }

    // MARK: - isInlineSummaryEmpty

    @Test func isInlineSummaryEmpty_trueForWhitespaceOnlySummary() {
        let task = Task(summary: "  \n  ")
        #expect(task.isInlineSummaryEmpty)
    }

    @Test func isInlineSummaryEmpty_falseForNonEmptySummary() {
        let task = Task(summary: "hello")
        #expect(!task.isInlineSummaryEmpty)
    }
}
