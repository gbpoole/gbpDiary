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
