import Testing
@testable import gbpDiary

@Suite("TaskTimeReport")
struct TaskTimeReportTests {
    @Test func entriesOnly_sumsEntries() {
        #expect(TaskTimeReport.totalHours(entryHours: 2.5, hasEntries: true, legacyHours: nil, blockNets: []) == 2.5)
    }

    @Test func blocksOnly_sumsNet() {
        // No entries, but backing focus blocks → sum of their net hours (legacy ignored).
        #expect(TaskTimeReport.totalHours(entryHours: 0, hasEntries: false, legacyHours: 99, blockNets: [3, 1.5]) == 4.5)
    }

    @Test func entriesPlusBlocks_sumsBoth() {
        #expect(TaskTimeReport.totalHours(entryHours: 2, hasEntries: true, legacyHours: nil, blockNets: [4]) == 6)
    }

    @Test func legacyFallback_onlyWhenNoEntriesAndNoBlocks() {
        #expect(TaskTimeReport.totalHours(entryHours: 0, hasEntries: false, legacyHours: 4, blockNets: []) == 4)
    }

    @Test func zeroWhenNothingAtAll() {
        #expect(TaskTimeReport.totalHours(entryHours: 0, hasEntries: false, legacyHours: nil, blockNets: []) == 0)
    }

    @Test func entriesWinOverLegacy() {
        // Legacy duration is ignored once real entries exist.
        #expect(TaskTimeReport.totalHours(entryHours: 1, hasEntries: true, legacyHours: 4, blockNets: []) == 1)
    }
}
