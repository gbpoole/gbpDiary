import Foundation
import Testing
@testable import gbpDiary

// Narrowing the Timesheet by project. The point of these tests is that the SAME selection narrows the
// report and the exported content identically — a filtered export that quietly carried other projects'
// minutes would be worse than no filter at all.
struct TimesheetFilterTests {
    private let cal = Calendar(identifier: .gregorian)
    private func d(_ day: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 1, day: day))! }

    private func row(_ title: String, _ hours: Double) -> TimesheetRow {
        TimesheetRow(id: UUID(), kind: .task, title: title, hours: hours, date: d(5))
    }
    private func node(_ name: String, _ hours: Double, id: UUID = UUID(),
                      children: [TimesheetNode] = [], unattributed: Bool = false) -> TimesheetNode {
        TimesheetNode(id: id, key: name, name: name, ownHours: hours, distinctWeeks: 1,
                      rows: [row("work on \(name)", hours)], children: children,
                      isUnattributed: unattributed)
    }

    // MARK: report

    @Test func emptySelectionMeansNoFilter() {
        let report = TimesheetReport(nodes: [node("NODES", 3), node("MAP", 2)], interval: nil)
        #expect(TimesheetFilter.apply(report, selected: []).nodes.map(\.name) == ["NODES", "MAP"])
    }

    @Test func selectingAProjectDropsTheOthers() {
        let nodes = node("NODES", 3)
        let report = TimesheetReport(nodes: [nodes, node("MAP", 2)], interval: nil)
        let filtered = TimesheetFilter.apply(report, selected: [nodes.id])
        #expect(filtered.nodes.map(\.name) == ["NODES"])
        #expect(filtered.totalOwnHours == 3)
    }

    // Asking for a parent means its subprojects too — that's how the hours already roll up.
    @Test func selectingAParentKeepsItsWholeSubtree() {
        let child = node("Ingest", 6)
        let parent = node("Pawsey", 1, children: [child])
        let report = TimesheetReport(nodes: [parent, node("MAP", 2)], interval: nil)
        let filtered = TimesheetFilter.apply(report, selected: [parent.id])
        #expect(filtered.nodes.map(\.name) == ["Pawsey"])
        #expect(filtered.nodes[0].children.map(\.name) == ["Ingest"])
        #expect(filtered.totalOwnHours == 7)
    }

    // Selecting only the child promotes it: no ancestor wrapper contributing hours you didn't ask for.
    @Test func selectingOnlyASubprojectPromotesItToARoot() {
        let child = node("Ingest", 6)
        let parent = node("Pawsey", 1, children: [child])
        let report = TimesheetReport(nodes: [parent], interval: nil)
        let filtered = TimesheetFilter.apply(report, selected: [child.id])
        #expect(filtered.nodes.map(\.name) == ["Ingest"])
        #expect(filtered.totalOwnHours == 6)        // the parent's own hour is not included
    }

    @Test func severalSelectionsAreKeptInOrder() {
        let a = node("Alpha", 1), b = node("Beta", 2), c = node("Gamma", 3)
        let report = TimesheetReport(nodes: [a, b, c], interval: nil)
        #expect(TimesheetFilter.apply(report, selected: [a.id, c.id]).nodes.map(\.name) == ["Alpha", "Gamma"])
    }

    // The unattributed bucket isn't a project, so a filtered view never carries it.
    @Test func unattributedIsDroppedWhileFiltering() {
        let nodes = node("NODES", 3)
        let report = TimesheetReport(nodes: [nodes, node("Unattributed", 2, unattributed: true)],
                                     interval: nil)
        #expect(TimesheetFilter.apply(report, selected: [nodes.id]).nodes.map(\.name) == ["NODES"])
        // …but it is still there when nothing is selected.
        #expect(TimesheetFilter.apply(report, selected: []).nodes.count == 2)
    }

    @Test func anUnknownSelectionKeepsNothing() {
        let report = TimesheetReport(nodes: [node("NODES", 3)], interval: nil)
        #expect(TimesheetFilter.apply(report, selected: [UUID()]).nodes.isEmpty)
    }

    // MARK: names

    @Test func projectNamesCoverTheSelectedSubtree() {
        let child = node("Ingest", 6)
        let parent = node("Pawsey", 1, children: [child])
        let report = TimesheetReport(nodes: [parent, node("MAP", 2)], interval: nil)
        #expect(TimesheetFilter.projectNames(in: report, selected: [parent.id]) == ["Pawsey", "Ingest"])
        #expect(TimesheetFilter.projectNames(in: report, selected: []).isEmpty)   // no filter
    }

    // MARK: content — the same selection must narrow the export identically

    private func content(meetingProjects: [[String]] = [], noteProjects: [String] = [],
                         conversationProjects: [[String]] = []) -> TimesheetExportSnapshot.FullContent {
        .init(notice: "n",
              meetings: meetingProjects.enumerated().map { index, projects in
                  .init(id: UUID(), summary: "m\(index)", meetingAt: d(5), durationHours: 1,
                        projects: projects, attendees: [], minutesMarkdown: "body")
              },
              notes: noteProjects.enumerated().map { index, project in
                  .init(id: UUID(), title: "n\(index)", project: project, day: nil,
                        updatedAt: d(5), markdown: "body")
              },
              conversations: conversationProjects.enumerated().map { index, projects in
                  .init(id: UUID(), subject: "c\(index)", projects: projects, otherParty: "",
                        importance: "low", loggedHours: 0, messages: [])
              })
    }

    @Test func contentIsNarrowedToTheSameProjects() {
        let bundle = content(meetingProjects: [["NODES"], ["MAP"], ["NODES", "MAP"]],
                             noteProjects: ["NODES", "MAP"],
                             conversationProjects: [["MAP"], ["NODES"]])
        let filtered = TimesheetFilter.apply(bundle, projectNames: ["NODES"])
        #expect(filtered.meetings.map(\.summary) == ["m0", "m2"])   // a shared meeting is kept
        #expect(filtered.notes.map(\.title) == ["n0"])
        #expect(filtered.conversations.map(\.subject) == ["c1"])
    }

    @Test func contentWithNoProjectIsDroppedWhileFiltering() {
        let bundle = content(meetingProjects: [[]], noteProjects: [""], conversationProjects: [[]])
        let filtered = TimesheetFilter.apply(bundle, projectNames: ["NODES"])
        #expect(filtered.meetings.isEmpty && filtered.notes.isEmpty && filtered.conversations.isEmpty)
    }

    @Test func noFilterLeavesTheContentUntouched() {
        let bundle = content(meetingProjects: [["NODES"], []], noteProjects: ["MAP"])
        #expect(TimesheetFilter.apply(bundle, projectNames: []) == bundle)
    }
}
