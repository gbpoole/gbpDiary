import Foundation
import Testing
@testable import gbpDiary

struct ChatTimeTotalsTests {
    private let cal = Calendar(identifier: .gregorian)
    private func d(_ day: Int) -> Date { cal.date(from: DateComponents(year: 2024, month: 6, day: day, hour: 10))! }
    private var interval: Range<Date> { d(8)..<d(15) }

    @Test func sumsOnlyInIntervalRecords() {
        let records = [
            ChatTimeRecord(sourceKey: "a", date: d(10), hours: 2.0, projectNames: ["NODES - 2026B"]),
            ChatTimeRecord(sourceKey: "b", date: d(12), hours: 1.5, projectNames: ["NODES - 2026B"]),
            ChatTimeRecord(sourceKey: "c", date: d(1),  hours: 9.0, projectNames: ["NODES - 2026B"]), // before window
        ]
        let totals = ChatTimeTotals.compute(records: records, interval: interval)
        #expect(totals.overall == 3.5)
        #expect(totals.perProject == [ChatProjectHours(name: "NODES - 2026B", hours: 3.5)])
    }

    @Test func dedupesBySourceKey() {
        // The same underlying record projected twice must not double-count.
        let records = [
            ChatTimeRecord(sourceKey: "x", date: d(10), hours: 2.0, projectNames: ["P"]),
            ChatTimeRecord(sourceKey: "x", date: d(10), hours: 2.0, projectNames: ["P"]),
        ]
        #expect(ChatTimeTotals.compute(records: records, interval: interval).overall == 2.0)
    }

    @Test func perProjectDescendingAndProjectFilter() {
        let records = [
            ChatTimeRecord(sourceKey: "a", date: d(10), hours: 1.0, projectNames: ["Alpha"]),
            ChatTimeRecord(sourceKey: "b", date: d(11), hours: 3.0, projectNames: ["Beta"]),
        ]
        let all = ChatTimeTotals.compute(records: records, interval: interval)
        #expect(all.perProject == [ChatProjectHours(name: "Beta", hours: 3.0), ChatProjectHours(name: "Alpha", hours: 1.0)])
        let onlyAlpha = ChatTimeTotals.compute(records: records, interval: interval, projectName: "alpha")
        #expect(onlyAlpha.overall == 1.0)
    }

    @Test func empty_whenNoInIntervalRecords() {
        let records = [ChatTimeRecord(sourceKey: "a", date: d(1), hours: 5.0, projectNames: ["P"])]
        let totals = ChatTimeTotals.compute(records: records, interval: interval)
        #expect(totals.isEmpty)
        #expect(totals.authoritativeBlock(intervalLabel: "this week") == nil)
    }

    @Test func authoritativeBlock_formatsFigures() {
        let records = [ChatTimeRecord(sourceKey: "a", date: d(10), hours: 12.5, projectNames: ["NODES - 2026B"])]
        let block = ChatTimeTotals.compute(records: records, interval: interval).authoritativeBlock(intervalLabel: "this week")
        #expect(block == "Computed time totals for this week (authoritative — report these exact figures): NODES - 2026B — 12.5h; Total — 12.5h")
    }
}
