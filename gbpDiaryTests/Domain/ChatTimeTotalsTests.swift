import Foundation
import Testing
@testable import gbpDiary

// ChatTimeTotals is now a thin renderer over the canonical TimeLedger — the aggregation math itself is
// covered by TimeLedgerTests. These test the Chat-facing filtering + rendering.
struct ChatTimeTotalsTests {
    private let cal = Calendar(identifier: .gregorian)

    private func ledger(_ project: [LedgerProjectHours], overall: Double = 0) -> LedgerResult {
        LedgerResult(perProject: project, standardTotal: overall, overtime: 0, blockNet: [:])
    }

    @Test func from_filtersToOneProject_caseInsensitive() {
        let l = ledger([
            LedgerProjectHours(name: "NODES - 2026B", hours: 4, distinctWeeks: 3),
            LedgerProjectHours(name: "Other Project", hours: 1, distinctWeeks: 1),
        ])
        let all = ChatTimeTotals.from(ledger: l, projectName: nil)
        #expect(all.overall == 5)
        let nodes = ChatTimeTotals.from(ledger: l, projectName: "nodes - 2026b")
        #expect(nodes.overall == 4)
        #expect(nodes.perProject.map(\.name) == ["NODES - 2026B"])
    }

    @Test func report_singleProjectAndPerProject() {
        let single = ChatTimeTotals(perProject: [LedgerProjectHours(name: "NODES", hours: 12.5, distinctWeeks: 3)], overall: 12.5)
        #expect(single.report(intervalLabel: "last month", projectName: "NODES")
            == "You logged 12.5h on NODES over last month — active in 3 weeks.")
        let many = ChatTimeTotals(perProject: [
            LedgerProjectHours(name: "NODES", hours: 12, distinctWeeks: 3),
            LedgerProjectHours(name: "Other", hours: 2, distinctWeeks: 1)], overall: 14)
        let text = many.report(intervalLabel: nil, projectName: nil)
        #expect(text.contains("NODES — 12h, active in 3 weeks"))
        #expect(text.contains("Other — 2h, active in 1 week"))
        #expect(text.contains("Total — 14h"))
    }

    @Test func emptyReport_explainsScopeAndWindow() {
        let noTime = ChatTimeTotals.emptyReport(interval: nil, intervalLabel: "last week", projectName: nil,
                                                overallHours: 0, calendar: cal)
        #expect(noTime.contains("on any project for last week"))
        #expect(noTime.contains("No logged time was found at all"))

        let d = { (day: Int) in self.cal.date(from: DateComponents(year: 2024, month: 6, day: day))! }
        let hasOther = ChatTimeTotals.emptyReport(interval: d(8)..<d(15), intervalLabel: "last week",
                                                  projectName: "NODES", overallHours: 5, calendar: cal)
        #expect(hasOther.contains("on NODES for last week"))
        #expect(hasOther.contains("5h logged in total"))
    }

    @Test func authoritativeBlock_formatsFigures() {
        let totals = ChatTimeTotals(perProject: [LedgerProjectHours(name: "NODES - 2026B", hours: 12.5, distinctWeeks: 1)], overall: 12.5)
        #expect(totals.authoritativeBlock(intervalLabel: "this week")
            == "Computed time totals for this week (authoritative — report these exact figures): NODES - 2026B — 12.5h; Total — 12.5h")
        #expect(ChatTimeTotals(perProject: [], overall: 0).authoritativeBlock(intervalLabel: "this week") == nil)
    }
}
