import Foundation
import Testing
@testable import gbpDiary

struct TimesheetExportTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return c
    }()
    private func d(_ day: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 1, day: day))! }

    private func row(_ title: String, _ hours: Double, kind: TimesheetRowKind = .task,
                     details: [TimesheetDetail] = [], status: String? = nil) -> TimesheetRow {
        TimesheetRow(id: UUID(), kind: kind, title: title, hours: hours, date: d(5), status: status,
                     details: details)
    }
    private func ledger(_ standard: Double, overtime: Double = 0) -> LedgerResult {
        LedgerResult(perProject: [], standardTotal: standard, overtime: overtime, blockNet: [:])
    }

    @Test func periodLabel_namesAClosedWholeDayInterval() {
        #expect(TimesheetExport.periodLabel(d(5)..<d(10), calendar: cal) == "5 Jan 2026 – 9 Jan 2026")
        #expect(TimesheetExport.periodLabel(d(5)..<d(6), calendar: cal) == "5 Jan 2026")   // one day
    }

    @Test func composeMarkdown_hasTitleTotalsAndPerProjectSections() {
        let report = TimesheetReport(nodes: [
            TimesheetNode(id: UUID(), key: "a", name: "NODES", ownHours: 7.6, distinctWeeks: 1,
                          rows: [row("rebuild ingest", 7.6,
                                     details: [TimesheetDetail(text: "manifest v2", hours: 1),
                                               TimesheetDetail(text: "Unspecified work", hours: 6.6,
                                                               isUnspecified: true)]),
                                 row("data team sync", 1, kind: .meeting)]),
        ], interval: d(5)..<d(10))
        let md = TimesheetExport.composeMarkdown(report: report, ledger: ledger(8.6),
                                                 periodLabel: "5 Jan 2026 – 9 Jan 2026")
        #expect(md.hasPrefix("# Timesheet — 5 Jan 2026 – 9 Jan 2026"))
        #expect(md.contains("**Total:** 8.6h · 1.1d"))
        #expect(md.contains("## NODES — 7.6h"))
        #expect(md.contains("**Tasks**"))
        #expect(md.contains("- Worked on: rebuild ingest (7.6h)"))
        #expect(md.contains("    - manifest v2 (1h)"))
        #expect(md.contains("    - Unspecified work (6.6h)"))   // details in FULL, unlike the screen
        #expect(md.contains("**Meetings**"))
    }

    @Test func composeMarkdown_includesProseWhenCached() {
        let id = UUID()
        let report = TimesheetReport(nodes: [
            TimesheetNode(id: id, key: "a", name: "NODES", ownHours: 3, distinctWeeks: 1, rows: [row("x", 3)]),
        ], interval: d(5)..<d(10))
        let md = TimesheetExport.composeMarkdown(report: report, ledger: ledger(3), periodLabel: "p",
                                                 prose: [id: "You rebuilt the ingest pipeline."])
        #expect(md.contains("You rebuilt the ingest pipeline."))
    }

    @Test func composeMarkdown_nestsSubprojectsAndNamesTheSubtreeTotal() {
        let child = TimesheetNode(id: UUID(), key: "c", name: "Ingest", ownHours: 6, distinctWeeks: 1,
                                  rows: [row("rebuild", 6)])
        let report = TimesheetReport(nodes: [
            TimesheetNode(id: UUID(), key: "p", name: "Pawsey", ownHours: 1, distinctWeeks: 1,
                          rows: [row("admin", 1)], children: [child]),
        ], interval: d(5)..<d(10))
        let md = TimesheetExport.composeMarkdown(report: report, ledger: ledger(7), periodLabel: "p")
        #expect(md.contains("## Pawsey — 1h"))
        #expect(md.contains("_Including subprojects: 7h._"))
        #expect(md.contains("### Ingest — 6h"))        // one heading level deeper
    }

    @Test func composeMarkdown_reportsOvertimeAndOverLogging() {
        let report = TimesheetReport(nodes: [
            TimesheetNode(id: UUID(), key: "a", name: "NODES", ownHours: 10, distinctWeeks: 1,
                          rows: [row("x", 10)]),
        ], interval: d(5)..<d(10))
        let md = TimesheetExport.composeMarkdown(report: report, ledger: ledger(7.6, overtime: 1),
                                                 periodLabel: "p")
        #expect(md.contains("**Overtime:** 1h (included in the total)"))
        #expect(md.contains("**Over-logged:** +1.4h"))   // 10 rows vs 8.6 ledger total
    }

    @Test func composeMarkdown_emptyReportSaysSo() {
        let md = TimesheetExport.composeMarkdown(report: TimesheetReport(), ledger: ledger(0),
                                                 periodLabel: "5 Jan 2026")
        #expect(md.contains("_No logged time in this period._"))
    }

    @Test func fileName_isSafeAndDescriptive() {
        #expect(TimesheetExport.fileName(periodLabel: "5 Jan 2026 – 9 Jan 2026")
                == "Timesheet 5 Jan 2026 - 9 Jan 2026.md")
        #expect(TimesheetExport.fileName(periodLabel: "") == "Timesheet.md")
    }
}
