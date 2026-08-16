import Foundation
import Testing
@testable import gbpDiary

struct ChatTimeTotalsTests {
    private let cal = Calendar(identifier: .gregorian)
    private func d(_ day: Int) -> Date { cal.date(from: DateComponents(year: 2024, month: 6, day: day, hour: 10))! }
    private var interval: Range<Date> { d(8)..<d(15) }

    @Test func distinctWeeks_countsDistinctCalendarWeeks() {
        // d(3) and d(4) are the same week; d(11) is the next week → 2 distinct weeks for the project.
        let records = [
            ChatTimeRecord(sourceKey: "a", date: d(3),  hours: 1, projectNames: ["P"]),
            ChatTimeRecord(sourceKey: "b", date: d(4),  hours: 1, projectNames: ["P"]),
            ChatTimeRecord(sourceKey: "c", date: d(11), hours: 1, projectNames: ["P"]),
        ]
        let totals = ChatTimeTotals.compute(records: records, calendar: cal)   // all time
        #expect(totals.perProject.first?.distinctWeeks == 2)
        #expect(totals.perProject.first?.hours == 3)
    }

    @Test func compute_nilInterval_isAllTime() {
        let records = [
            ChatTimeRecord(sourceKey: "a", date: d(1),  hours: 2, projectNames: ["P"]),   // before the usual window
            ChatTimeRecord(sourceKey: "b", date: d(30), hours: 3, projectNames: ["P"]),   // after
        ]
        #expect(ChatTimeTotals.compute(records: records, calendar: cal).overall == 5)
    }

    @Test func report_singleProjectAndPerProject() {
        let single = ChatTimeTotals(perProject: [ChatProjectHours(name: "NODES", hours: 12.5, distinctWeeks: 3)], overall: 12.5)
        #expect(single.report(intervalLabel: "last month", projectName: "NODES")
            == "You logged 12.5h on NODES over last month — active in 3 weeks.")
        let many = ChatTimeTotals(perProject: [
            ChatProjectHours(name: "NODES", hours: 12, distinctWeeks: 3),
            ChatProjectHours(name: "Other", hours: 2, distinctWeeks: 1)], overall: 14)
        let text = many.report(intervalLabel: nil, projectName: nil)
        #expect(text.contains("NODES — 12h, active in 3 weeks"))
        #expect(text.contains("Other — 2h, active in 1 week"))
        #expect(text.contains("Total — 14h"))
        #expect(ChatTimeTotals(perProject: [], overall: 0).report(intervalLabel: "last week", projectName: nil)
            == "No time is logged over last week.")
    }

    @Test func sumsOnlyInIntervalRecords() {
        let records = [
            ChatTimeRecord(sourceKey: "a", date: d(10), hours: 2.0, projectNames: ["NODES - 2026B"]),
            ChatTimeRecord(sourceKey: "b", date: d(12), hours: 1.5, projectNames: ["NODES - 2026B"]),
            ChatTimeRecord(sourceKey: "c", date: d(1),  hours: 9.0, projectNames: ["NODES - 2026B"]), // before window
        ]
        let totals = ChatTimeTotals.compute(records: records, interval: interval, calendar: cal)
        #expect(totals.overall == 3.5)
        #expect(totals.perProject.map { [$0.name: $0.hours] } == [["NODES - 2026B": 3.5]])
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
        let all = ChatTimeTotals.compute(records: records, interval: interval, calendar: cal)
        #expect(all.perProject.map(\.name) == ["Beta", "Alpha"])
        #expect(all.perProject.map(\.hours) == [3.0, 1.0])
        let onlyAlpha = ChatTimeTotals.compute(records: records, interval: interval, projectName: "alpha", calendar: cal)
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
