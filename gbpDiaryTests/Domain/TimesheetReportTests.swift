import Foundation
import Testing
@testable import gbpDiary

struct TimesheetReportTests {
    private let cal = Calendar(identifier: .gregorian)
    private func d(_ day: Int) -> Date { cal.date(from: DateComponents(year: 2024, month: 1, day: day))! }

    private func taskRow(_ title: String, _ hours: Double, day: Int = 3, done: Bool = false,
                         details: [TimesheetDetail] = []) -> TimesheetRow {
        TimesheetRow(id: UUID(), kind: .task, title: title, hours: hours, date: d(day),
                     status: done ? "✓ 3 Jan" : nil, details: details)
    }
    private func meetingRow(_ title: String, _ hours: Double) -> TimesheetRow {
        TimesheetRow(id: UUID(), kind: .meeting, title: title, hours: hours, date: d(3))
    }
    private func node(_ name: String, hours: Double, weeks: Int = 1, rows: [TimesheetRow] = [],
                      unlogged: [TimesheetRow] = [], extracts: [TimesheetExtract] = [],
                      children: [TimesheetNode] = [], unattributed: Bool = false) -> TimesheetNode {
        TimesheetNode(id: UUID(), key: name, name: name, ownHours: hours, distinctWeeks: weeks,
                      rows: rows, unloggedRows: unlogged, extracts: extracts, children: children,
                      isUnattributed: unattributed)
    }

    // MARK: rows

    @Test func bulletLabel_namesEachKindAndCarriesHours() {
        #expect(meetingRow("sprint", 1).bulletLabel == "Meeting: sprint (1h)")
        #expect(taskRow("EoI draft", 3, done: true).bulletLabel == "Completed: EoI draft (3h)")
        #expect(taskRow("ingest rebuild", 6.6).bulletLabel == "Worked on: ingest rebuild (6.6h)")
        let convo = TimesheetRow(id: UUID(), kind: .conversation, title: "grant reply", hours: 0.25,
                                 date: d(3), badge: "1 sent · 2 recv [H]")
        #expect(convo.bulletLabel == "Email: grant reply 1 sent · 2 recv [H] (0.3h)")
        let orphan = TimesheetRow(id: UUID(), kind: .completedNoTime, title: "tidy repo", hours: 0, date: d(3))
        #expect(orphan.bulletLabel == "Completed: tidy repo")   // no hours shown when there are none
    }

    @Test func detailLabel_showsTimeWhenItHasAny() {
        #expect(TimesheetDetail(text: "manifest v2", hours: 1.5).label == "manifest v2 (1.5h)")
        #expect(TimesheetDetail(text: "Unspecified work", hours: 6.6, isUnspecified: true).label
                == "Unspecified work (6.6h)")
        #expect(TimesheetDetail(text: "no time", hours: 0).label == "no time")
    }

    // MARK: node arithmetic

    @Test func rowsHours_isTheHoursTheRowsAccountFor() {
        let n = node("NODES", hours: 4, rows: [taskRow("a", 3), meetingRow("b", 1)])
        #expect(n.rowsHours == 4)
        #expect(n.ownHours == n.rowsHours)       // the invariant the projection must maintain
    }

    @Test func subtreeHours_sumsOwnPlusDescendants() {
        let leaf = node("Ingest", hours: 6)
        let mid = node("Pipeline", hours: 2, children: [leaf])
        let root = node("Pawsey", hours: 1, children: [mid])
        #expect(root.subtreeHours == 9)
        #expect(root.ownHours == 1)              // own is NOT the subtree
        #expect(mid.subtreeHours == 8)
    }

    @Test func subtreeRows_coverDescendants_soAParentCanSummariseBeneathIt() {
        let leaf = node("Ingest", hours: 6, rows: [taskRow("rebuild", 6)])
        let root = node("Pawsey", hours: 1, rows: [meetingRow("sync", 1)], children: [leaf])
        #expect(root.subtreeRows.map(\.title).sorted() == ["rebuild", "sync"])
    }

    @Test func groups_orderKindsAndDropEmptyOnes() {
        let n = node("NODES", hours: 4, rows: [meetingRow("sync", 1), taskRow("a", 3)],
                     unlogged: [TimesheetRow(id: UUID(), kind: .completedNoTime, title: "orphan",
                                             hours: 0, date: d(3))])
        #expect(n.groups.map(\.title) == ["Tasks", "Meetings", "Completed, no time logged"])
    }

    @Test func headerLine_showsHoursDaysWeeks() {
        #expect(node("NODES", hours: 15.2, weeks: 3).headerLine == "NODES — 15.2h · 2d · 3 weeks")
    }

    // MARK: report

    @Test func render_headerThenBullets_nodesInOrder() {
        let report = TimesheetReport(nodes: [
            node("NODES", hours: 12, weeks: 2, rows: [meetingRow("review", 1), taskRow("EoI draft", 11, done: true)]),
            node("Other", hours: 2),
        ], interval: d(1)..<d(10))
        let text = report.render()
        #expect(text.contains("NODES — 12h"))
        #expect(text.contains("• Meeting: review (1h)"))
        #expect(text.contains("• Completed: EoI draft (11h)"))
        #expect(text.contains("Other — 2h"))      // a node with no rows shows just its header
        #expect(text.range(of: "NODES")!.lowerBound < text.range(of: "Other")!.lowerBound)
    }

    @Test func nodeMatching_isCaseInsensitiveAndSearchesChildren() {
        let report = TimesheetReport(nodes: [
            node("Pawsey", hours: 1, children: [node("NODES - 2026B", hours: 1)]),
        ], interval: nil)
        #expect(report.node(matching: "nodes - 2026b")?.name == "NODES - 2026B")
        #expect(report.node(matching: "missing") == nil)
    }

    @Test func narrativeBlock_bulletsGroupedByProject_noTimeHeader_optionallyScoped() {
        let report = TimesheetReport(nodes: [
            node("NODES", hours: 12, weeks: 2, rows: [meetingRow("review", 1)]),
            node("Other", hours: 2),
        ], interval: nil)
        let all = report.narrativeBlock()
        #expect(all.contains("NODES:\n• Meeting: review (1h)"))
        #expect(!all.contains("12h"))       // no time header — the report already states the hours
        #expect(!all.contains("Other"))     // a node with no rows contributes nothing
        #expect(report.narrativeBlock(projectName: "nodes") == "NODES:\n• Meeting: review (1h)")
        #expect(report.narrativeBlock(projectName: "missing") == "")
    }

    @Test func narrativeBlock_includesCommentDetails() {
        let row = taskRow("rebuild", 6.6, details: [TimesheetDetail(text: "manifest v2", hours: 1.5)])
        let report = TimesheetReport(nodes: [node("NODES", hours: 6.6, rows: [row])], interval: nil)
        #expect(report.narrativeBlock().contains("  – manifest v2 (1.5h)"))
    }

    // Chat's bound is STRUCTURAL: the unattributed node and every mined extract are unreachable from the
    // narrative block, so Chat's prompt context can't be flooded by them.
    // Found by running it: the model turned the bookkeeping label into prose — "You worked on X, including
    // unspecified work." It belongs on screen and in the export, never in a prompt or in Chat.
    @Test func modelFacingRenderings_omitTheUnspecifiedWorkLabel() {
        let row = taskRow("rebuild", 7.6, details: [TimesheetDetail(text: "manifest v2", hours: 1),
                                                    TimesheetDetail(text: "Unspecified work", hours: 6.6,
                                                                    isUnspecified: true)])
        let n = node("NODES", hours: 7.6, rows: [row])
        let report = TimesheetReport(nodes: [n], interval: nil)
        #expect(!report.narrativeBlock().contains("Unspecified work"))
        #expect(report.narrativeBlock().contains("manifest v2 (1h)"))      // described comments stay
        #expect(!TimesheetReport.phrasingPrompt(node: n).contains("Unspecified work"))
        #expect(TimesheetReport.phrasingPrompt(node: n).contains("manifest v2 (1h)"))
        // The row itself keeps it — the screen and the export still say what is undescribed.
        #expect(row.details.contains { $0.isUnspecified })
    }

    @Test func narrativeBlock_excludesUnattributedAndExtracts() {
        let extract = TimesheetExtract(id: UUID(), title: "Minutes: sync", text: "agreed the manifest", date: d(3))
        let report = TimesheetReport(nodes: [
            node("NODES", hours: 3, rows: [taskRow("a", 3)], extracts: [extract]),
            node("Unattributed", hours: 2, rows: [taskRow("stray", 2)], unattributed: true),
        ], interval: nil)
        let block = report.narrativeBlock()
        #expect(block.contains("NODES:"))
        #expect(!block.contains("agreed the manifest"))
        #expect(!block.contains("Unattributed"))
        #expect(!block.contains("stray"))
    }

    @Test func totalOwnHours_sumsEveryNodeIncludingChildrenAndUnattributed() {
        let report = TimesheetReport(nodes: [
            node("Pawsey", hours: 1, children: [node("Ingest", hours: 6)]),
            node("Unattributed", hours: 2, unattributed: true),
        ], interval: nil)
        #expect(report.totalOwnHours == 9)
    }

    @Test func phrasingPrompt_isStrictRephraseOnly_andCoversTheSubtree() {
        let leaf = node("Ingest", hours: 6, rows: [taskRow("rebuild", 6)])
        let extract = TimesheetExtract(id: UUID(), title: "Minutes: sync", text: "agreed the manifest", date: d(3))
        let root = node("Pawsey", hours: 1, rows: [meetingRow("sync", 1)], extracts: [extract], children: [leaf])
        let prompt = TimesheetReport.phrasingPrompt(node: root)
        #expect(prompt.contains("Use ONLY these items"))
        #expect(prompt.contains("do not add, infer, embellish, or omit"))
        #expect(prompt.contains("Never state a figure that is not listed"))
        #expect(prompt.contains("second person"))        // the shared app-wide voice
        #expect(prompt.contains("simple past tense"))
        #expect(prompt.contains("Pawsey"))
        #expect(prompt.contains("• Meeting: sync (1h)"))
        #expect(prompt.contains("• Worked on: rebuild (6h)"))   // the subtree, not just this node
        #expect(prompt.contains("Minutes: sync: agreed the manifest"))
    }
}
