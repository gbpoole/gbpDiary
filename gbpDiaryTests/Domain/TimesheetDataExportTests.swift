import Foundation
import Testing
@testable import gbpDiary

// The JSON export exists so an external reader answers time questions with the APP's figures rather than
// re-deriving them from raw rows. These tests pin that: the numbers come from the report and the ledger
// untouched, the nesting survives, and the file round-trips.
struct TimesheetDataExportTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return c
    }()
    private func d(_ day: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 1, day: day))! }

    private func row(_ title: String, _ hours: Double, kind: TimesheetRowKind = .task,
                     details: [TimesheetDetail] = []) -> TimesheetRow {
        TimesheetRow(id: UUID(), kind: kind, title: title, hours: hours, date: d(5), status: nil,
                     details: details)
    }
    private func ledger(_ standard: Double, overtime: Double = 0) -> LedgerResult {
        LedgerResult(perProject: [], standardTotal: standard, overtime: overtime, blockNet: [:])
    }
    private func snapshot(_ report: TimesheetReport, _ result: LedgerResult,
                          prose: [UUID: String] = [:]) -> TimesheetExportSnapshot {
        TimesheetDataExport.snapshot(report: report, ledger: result, interval: d(5)..<d(10),
                                     periodLabel: "5 Jan 2026 – 9 Jan 2026", prose: prose,
                                     generatedAt: d(9))
    }

    @Test func totalsComeFromTheLedger_notFromSummingRows() {
        let report = TimesheetReport(nodes: [
            TimesheetNode(id: UUID(), key: "a", name: "NODES", ownHours: 10, distinctWeeks: 1,
                          rows: [row("x", 10)]),
        ], interval: d(5)..<d(10))
        // Over-logged: the rows sum to 10 while the ledger's own total is 8.6.
        let snap = snapshot(report, ledger(7.6, overtime: 1))
        #expect(snap.totals.hours == 8.6)                     // the ledger's figure is the headline
        #expect(snap.totals.overtimeHours == 1)
        #expect(snap.totals.standardHours == 7.6)
        #expect(snap.totals.projectHoursTotal == 10)
        #expect(abs(snap.totals.overLoggedHours - 1.4) < 0.0001)   // the difference is stated, not hidden
        #expect(abs(snap.totals.days - 8.6 / 7.6) < 0.0001)
    }

    @Test func overLoggedIsZeroWhenTheRowsAgree() {
        let report = TimesheetReport(nodes: [
            TimesheetNode(id: UUID(), key: "a", name: "NODES", ownHours: 7.6, distinctWeeks: 1,
                          rows: [row("x", 7.6)]),
        ], interval: d(5)..<d(10))
        #expect(snapshot(report, ledger(7.6)).totals.overLoggedHours == 0)
    }

    @Test func nestingAndOwnVsSubtreeHoursSurvive() {
        let child = TimesheetNode(id: UUID(), key: "c", name: "Ingest", ownHours: 6, distinctWeeks: 1,
                                  rows: [row("rebuild", 6)])
        let report = TimesheetReport(nodes: [
            TimesheetNode(id: UUID(), key: "p", name: "Pawsey", ownHours: 1, distinctWeeks: 2,
                          rows: [row("admin", 1)], children: [child]),
        ], interval: d(5)..<d(10))
        let root = snapshot(report, ledger(7)).projects[0]
        #expect(root.name == "Pawsey")
        #expect(root.hours == 1)                 // own work only
        #expect(root.subtreeHours == 7)          // including the subproject
        #expect(root.distinctWeeks == 2)
        #expect(root.children.map(\.name) == ["Ingest"])
        #expect(root.children[0].hours == 6)
    }

    @Test func rowsCarryKindDetailsAndPresenceRows() {
        let worked = row("rebuild", 6.6, details: [
            TimesheetDetail(text: "manifest v2", hours: 1),
            TimesheetDetail(text: "Unspecified work", hours: 5.6, isUnspecified: true),
        ])
        let orphan = TimesheetRow(id: UUID(), kind: .completedNoTime, title: "tidy", hours: 0, date: d(6))
        let report = TimesheetReport(nodes: [
            TimesheetNode(id: UUID(), key: "a", name: "NODES", ownHours: 6.6, distinctWeeks: 1,
                          rows: [worked], unloggedRows: [orphan]),
        ], interval: d(5)..<d(10))
        let node = snapshot(report, ledger(6.6)).projects[0]
        #expect(node.rows.map(\.kind) == ["task", "completedNoTime"])   // presence rows included, at 0h
        #expect(node.rows[1].hours == 0)
        #expect(node.rows[0].details.map(\.text) == ["manifest v2", "Unspecified work"])
        #expect(node.rows[0].details[1].isUnspecified)
    }

    @Test func generatedProseIsAttachedByNode() {
        let id = UUID()
        let report = TimesheetReport(nodes: [
            TimesheetNode(id: id, key: "a", name: "NODES", ownHours: 3, distinctWeeks: 1, rows: [row("x", 3)]),
        ], interval: d(5)..<d(10))
        let snap = snapshot(report, ledger(3), prose: [id: "You rebuilt the pipeline."])
        #expect(snap.projects[0].summary == "You rebuilt the pipeline.")
        #expect(snapshot(report, ledger(3)).projects[0].summary == "")   // "" when not generated,
                                                                 // never a missing key
    }

    @Test func unattributedIsFlaggedSoAReaderCanSaySo() {
        let report = TimesheetReport(nodes: [
            TimesheetNode(id: TimesheetReport.unattributedID, key: TimeLedger.noProject,
                          name: "Unattributed", ownHours: 2, distinctWeeks: 1, rows: [row("stray", 2)],
                          isUnattributed: true),
        ], interval: d(5)..<d(10))
        #expect(snapshot(report, ledger(2)).projects[0].isUnattributed)
    }

    @Test func periodIsTheHalfOpenWholeDayInterval() {
        let snap = snapshot(TimesheetReport(), ledger(0))
        #expect(snap.period.start == d(5))
        #expect(snap.period.end == d(10))        // exclusive
        #expect(snap.period.label == "5 Jan 2026 – 9 Jan 2026")
    }

    @Test func jsonRoundTripsAndIsStable() throws {
        let child = TimesheetNode(id: UUID(), key: "c", name: "Ingest", ownHours: 6, distinctWeeks: 1,
                                  rows: [row("rebuild", 6)],
                                  extracts: [TimesheetExtract(id: UUID(), title: "Minutes: sync",
                                                              text: "agreed the manifest", date: d(6))])
        let report = TimesheetReport(nodes: [
            TimesheetNode(id: UUID(), key: "p", name: "Pawsey", ownHours: 1, distinctWeeks: 1,
                          rows: [row("admin", 1)], children: [child]),
        ], interval: d(5)..<d(10))
        let original = snapshot(report, ledger(7))
        let data = try TimesheetDataExport.encode(original)
        #expect(try TimesheetDataExport.decode(data) == original)
        // Encoding twice is byte-identical, so the file diffs cleanly.
        #expect(try TimesheetDataExport.encode(original) == data)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"formatVersion\" : 1"))
        #expect(text.contains("2026-01-09T00:00:00Z"))       // ISO-8601 dates
        #expect(text.contains("agreed the manifest"))
    }

    // Swift's encoder omits nil optionals, so a reader indexing a key that vanished simply breaks (it
    // broke one while this was being built). Absent strings must therefore be "", not missing keys.
    @Test func stringKeysAreAlwaysPresent() throws {
        let report = TimesheetReport(nodes: [
            TimesheetNode(id: UUID(), key: "a", name: "NODES", ownHours: 1, distinctWeeks: 1,
                          rows: [row("no status or badge", 1)]),   // both nil on the model side
        ], interval: d(5)..<d(10))
        let json = try JSONSerialization.jsonObject(
            with: TimesheetDataExport.encode(snapshot(report, ledger(1)))) as! [String: Any]
        let project = (json["projects"] as! [[String: Any]])[0]
        #expect(project["summary"] as? String == "")
        let row = (project["rows"] as! [[String: Any]])[0]
        #expect(row["status"] as? String == "")
        #expect(row["badge"] as? String == "")
    }

    @Test func formatVersionIsStamped() {
        #expect(snapshot(TimesheetReport(), ledger(0)).formatVersion == TimesheetDataExport.formatVersion)
        #expect(TimesheetDataExport.latestFileName == "timesheet-latest.json")
    }
}
