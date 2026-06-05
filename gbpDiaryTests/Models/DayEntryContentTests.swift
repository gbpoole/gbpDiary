import Foundation
import Testing
@testable import gbpDiary

@MainActor
struct DayEntryContentTests {
    @Test func inlineSummary_forNote_readsAndWritesText() {
        let entry = DayEntry(kind: .note, text: "initial")

        #expect(entry.inlineSummary == "initial")
        entry.inlineSummary = "updated"
        #expect(entry.text == "updated")
    }

    @Test func inlineSummary_forTask_readsAndWritesTaskSummary() {
        let task = Task(summary: "task A")
        let entry = DayEntry(kind: .task)
        entry.task = task

        #expect(entry.inlineSummary == "task A")
        entry.inlineSummary = "task B"
        #expect(task.summary == "task B")
        #expect(entry.inlineSummary == "task B")
    }

    @Test func inlineSummary_forMeeting_roundTripsEmptyAsNilSummary() {
        let minutes = Minutes(meetingAt: .now)
        minutes.summary = "sync"
        let entry = DayEntry(kind: .meeting)
        entry.minutes = minutes

        #expect(entry.inlineSummary == "sync")
        entry.inlineSummary = ""
        #expect(minutes.summary == nil)
    }

@Test func isInlineSummaryEmpty_trimsWhitespaceAndNewlines() {
        let noteEntry = DayEntry(kind: .note, text: "  \n ")
        #expect(noteEntry.isInlineSummaryEmpty)

        noteEntry.inlineSummary = "x"
        #expect(!noteEntry.isInlineSummaryEmpty)
    }
}
