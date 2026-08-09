import SwiftUI
import SwiftData

// Invisible global driver (placed once in WorkspaceView): keeps recurrence + deferral consistent no
// matter where a task was completed.
//   • A completed task with a `recurrenceRule` spawns its next instance (due advanced by the rule) and
//     clears its own rule so it never respawns; the new instance carries the rule forward.
//   • An open task past its `until` date is auto-cancelled.
struct TaskRecurrenceDriver: View {
    @Environment(\.modelContext) private var context
    @Query private var tasks: [Task]

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { sweep() }
            .onChange(of: triggerKey) { sweep() }
    }

    // Re-fires the sweep when a recurring task completes or an until date lapses.
    private var triggerKey: String {
        tasks.filter { needsSpawn($0) || needsCancel($0) }
            .map(\.id.uuidString).sorted().joined()
    }

    private func needsSpawn(_ t: Task) -> Bool {
        t.status == .completed && RecurrenceRule.parse(t.recurrenceRule ?? "") != nil
    }
    private func needsCancel(_ t: Task) -> Bool {
        t.isOpen && (t.until.map { $0 < Date() } ?? false)
    }

    private func sweep() {
        for t in tasks where needsSpawn(t) { spawnNext(t) }
        for t in tasks where needsCancel(t) { t.markCancelled() }
    }

    private func spawnNext(_ t: Task) {
        guard let rule = RecurrenceRule.parse(t.recurrenceRule ?? "") else { return }
        let base = t.dueAt ?? t.completedAt ?? Date()
        let next = Task(summary: t.summary)
        next.notes = t.notes
        next.priorityRaw = t.priorityRaw
        next.project = t.project
        next.assignee = t.assignee
        next.tags = t.tags
        next.dueAt = rule.next(after: base)
        next.recurrenceRule = t.recurrenceRule
        next.recurrenceParentID = t.id
        context.insert(next)
        t.recurrenceRule = nil   // the completed occurrence is history; the new one carries the rule
    }
}
