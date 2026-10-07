import Foundation
import Testing
@testable import gbpDiary

struct TimesheetSummaryPlanningTests {
    private let cal = Calendar(identifier: .gregorian)
    private func d(_ day: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 1, day: day))! }

    private func row(_ title: String, _ hours: Double, details: [TimesheetDetail] = []) -> TimesheetRow {
        TimesheetRow(id: UUID(), kind: .task, title: title, hours: hours, date: d(5), details: details)
    }
    private func node(rows: [TimesheetRow], extracts: [TimesheetExtract] = [],
                      children: [TimesheetNode] = []) -> TimesheetNode {
        TimesheetNode(id: UUID(), key: "k", name: "NODES", ownHours: rows.reduce(0) { $0 + $1.hours },
                      distinctWeeks: 1, rows: rows, extracts: extracts, children: children)
    }

    @Test func promptVersion_foldsTheSharedVoiceVersion() {
        #expect(TimesheetSummaryPlanning.promptVersion
                == TimesheetSummaryPlanning.promptBase + AISummaryStyle.version)
    }

    @Test func fingerprint_isOrderIndependent() {
        let a = row("a", 1), b = row("b", 2)
        #expect(TimesheetSummaryPlanning.fingerprint(node: node(rows: [a, b]))
                == TimesheetSummaryPlanning.fingerprint(node: node(rows: [b, a])))
    }

    @Test func fingerprint_changesWithHoursCommentsAndExtracts() {
        let base = node(rows: [row("a", 1)])
        let more = node(rows: [row("a", 2)])
        #expect(TimesheetSummaryPlanning.fingerprint(node: base)
                != TimesheetSummaryPlanning.fingerprint(node: more))

        let commented = node(rows: [row("a", 1, details: [TimesheetDetail(text: "note", hours: 1)])])
        #expect(TimesheetSummaryPlanning.fingerprint(node: base)
                != TimesheetSummaryPlanning.fingerprint(node: commented))

        let withExtract = node(rows: [row("a", 1)],
                               extracts: [TimesheetExtract(id: UUID(), title: "Minutes: x", text: "y", date: d(5))])
        #expect(TimesheetSummaryPlanning.fingerprint(node: base)
                != TimesheetSummaryPlanning.fingerprint(node: withExtract))
    }

    // A parent's prose covers its subtree, so a change beneath it must refresh the parent's paragraph too.
    @Test func fingerprint_coversTheSubtree() {
        let child = node(rows: [row("child", 1)])
        let parent = node(rows: [row("parent", 1)], children: [child])
        let changedChild = node(rows: [row("child", 4)])
        let parentChanged = node(rows: [row("parent", 1)], children: [changedChild])
        #expect(TimesheetSummaryPlanning.fingerprint(node: parent)
                != TimesheetSummaryPlanning.fingerprint(node: parentChanged))
    }

    @Test func needsSummary_whenMissingStaleOrPending() {
        let fp = "fp"
        // Nothing stored yet.
        #expect(TimesheetSummaryPlanning.needsSummary(hasContent: true, state: nil, storedFingerprint: nil,
                                                      storedPromptVersion: nil, fingerprint: fp))
        // Stored but the material changed.
        #expect(TimesheetSummaryPlanning.needsSummary(hasContent: true, state: .done,
                                                      storedFingerprint: "other", storedPromptVersion: 1,
                                                      fingerprint: fp, promptVersion: 1))
        // Stored but the prompt moved on.
        #expect(TimesheetSummaryPlanning.needsSummary(hasContent: true, state: .done, storedFingerprint: fp,
                                                      storedPromptVersion: 1, fingerprint: fp,
                                                      promptVersion: 2))
        // Left pending by an interrupted run.
        #expect(TimesheetSummaryPlanning.needsSummary(hasContent: true, state: .pending,
                                                      storedFingerprint: fp, storedPromptVersion: 1,
                                                      fingerprint: fp, promptVersion: 1))
    }

    @Test func needsSummary_isFalseWhenSettledOrEmpty() {
        let fp = "fp"
        #expect(!TimesheetSummaryPlanning.needsSummary(hasContent: true, state: .done, storedFingerprint: fp,
                                                       storedPromptVersion: 1, fingerprint: fp,
                                                       promptVersion: 1))
        // A failure must not spin: it stays settled until the material or the prompt changes.
        #expect(!TimesheetSummaryPlanning.needsSummary(hasContent: true, state: .failed, storedFingerprint: fp,
                                                       storedPromptVersion: 1, fingerprint: fp,
                                                       promptVersion: 1))
        // Nothing to summarise.
        #expect(!TimesheetSummaryPlanning.needsSummary(hasContent: false, state: nil, storedFingerprint: nil,
                                                       storedPromptVersion: nil, fingerprint: fp))
    }

    @Test func isExpired_afterFiveWeeksWithoutBeingGeneratedOrShown() {
        let now = d(5)
        let week: TimeInterval = 7 * 24 * 60 * 60
        #expect(!TimesheetSummaryPlanning.isExpired(touchedAt: now.addingTimeInterval(-4 * week), now: now))
        #expect(TimesheetSummaryPlanning.isExpired(touchedAt: now.addingTimeInterval(-6 * week), now: now))
        #expect(TimesheetSummaryPlanning.evictionWeeks == 5)
    }

    @Test func state_roundTripsThroughTheStoredRaw() {
        let record = TimesheetSummary(nodeID: UUID(), rangeStart: d(5), rangeEnd: d(10))
        #expect(record.state == .pending)
        record.state = .done
        #expect(record.summaryState == "done")
        record.summaryState = "nonsense"
        #expect(record.state == .pending)       // unknown raw falls back
    }

    @Test func matches_identifiesANodeAndPeriodExactly() {
        let id = UUID()
        let record = TimesheetSummary(nodeID: id, rangeStart: d(5), rangeEnd: d(10))
        #expect(record.matches(nodeID: id, interval: d(5)..<d(10)))
        #expect(!record.matches(nodeID: id, interval: d(5)..<d(11)))      // a different period
        #expect(!record.matches(nodeID: UUID(), interval: d(5)..<d(10)))  // a different project
    }
}
