import Foundation

// Narrowing the Timesheet to chosen projects — on screen and, identically, in what gets exported.
//
// The rules, once:
//   • An empty selection means NO filter (everything), not "nothing".
//   • Selecting a project takes its whole SUBTREE: asking for "Pawsey" means its subprojects too, which is
//     how the hours already roll up.
//   • A kept node whose parent is not kept is PROMOTED to a root, so the filtered report's displayed
//     hours still sum to its own total — no ancestor wrappers contributing hours you didn't ask for.
//   • The unattributed bucket is not a project, so it is dropped while a filter is active.
//   • The content bundle is filtered by the same selection, by project NAME, because `FullContent` carries
//     names — so the exported markdown tree contains exactly the projects the screen shows.
nonisolated enum TimesheetFilter {

    /// The report narrowed to `selected` (empty = unchanged).
    static func apply(_ report: TimesheetReport, selected: Set<UUID>) -> TimesheetReport {
        guard !selected.isEmpty else { return report }
        return TimesheetReport(nodes: keep(report.nodes, selected: selected), interval: report.interval)
    }

    private static func keep(_ nodes: [TimesheetNode], selected: Set<UUID>) -> [TimesheetNode] {
        nodes.flatMap { node -> [TimesheetNode] in
            if selected.contains(node.id) { return [node] }          // whole subtree, as-is
            return keep(node.children, selected: selected)           // promote kept descendants
        }
    }

    /// Every project name the selection covers, including descendants — the key the content bundle uses.
    static func projectNames(in report: TimesheetReport, selected: Set<UUID>) -> Set<String> {
        guard !selected.isEmpty else { return [] }
        return Set(apply(report, selected: selected).allNodes.map(\.name))
    }

    /// The content bundle narrowed to the same projects (empty = unchanged). Items with no project are
    /// dropped while a filter is active: they belong to the unattributed bucket, which isn't a selection.
    static func apply(_ content: TimesheetExportSnapshot.FullContent,
                      projectNames: Set<String>) -> TimesheetExportSnapshot.FullContent {
        guard !projectNames.isEmpty else { return content }
        func matches(_ projects: [String]) -> Bool { projects.contains { projectNames.contains($0) } }
        return .init(notice: content.notice,
                     meetings: content.meetings.filter { matches($0.projects) },
                     notes: content.notes.filter { projectNames.contains($0.project) },
                     conversations: content.conversations.filter { matches($0.projects) })
    }
}
