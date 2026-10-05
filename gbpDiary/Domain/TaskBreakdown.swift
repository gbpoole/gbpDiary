import Foundation
import SwiftData

// Materialises a parsed outline (`TaskOutlineParser.parse`) into a real task subtree — the second half
// of the hybrid breakdown workflow (parse text → create tasks). Kept out of the view so it can be
// tested against a real ModelContext.
//
// Inheritance rules, so a breakdown lands ready to work rather than needing re-triage:
//  • project and assignee are inherited from the parent unless the caller overrides them;
//  • `needsTriage` is inherited from the parent — decomposing an already-reviewed task yields reviewed
//    subtasks (they inherit its context), while a breakdown typed with no parent is fresh capture and
//    stays in the Inbox. Note the Inbox itself only ever holds top-level tasks, but the Reviewed table
//    hides any open task still flagged, so inheriting keeps new subtasks visible where they were made.
//  • siblings are appended after the parent's existing children, preserving outline order.
enum TaskBreakdown {

    /// Creates `outline` as a task subtree. Returns the newly created root tasks (outline top level).
    @discardableResult
    static func create(_ outline: [OutlineNode],
                       under parent: Task?,
                       project: Project? = nil,
                       assignee: Person? = nil,
                       in context: ModelContext) -> [Task] {
        guard !outline.isEmpty else { return [] }

        let inheritedProject = project ?? parent?.project
        let inheritedAssignee = assignee ?? parent?.assignee
        let inheritedTriage = parent?.needsTriage ?? true

        // Append after whatever the parent already has, so an existing breakdown isn't reshuffled.
        var nextSortOrder = (parent?.children.map(\.sortOrder).max()).map { $0 + 1 } ?? 0

        func build(_ nodes: [OutlineNode], parent: Task?, startingAt start: Int) -> [Task] {
            var order = start
            var created: [Task] = []
            for node in nodes {
                let task = makeRow(summary: node.summary, under: parent, project: inheritedProject,
                                   assignee: inheritedAssignee, inheritTriageFrom: inheritedTriage,
                                   sortOrder: order, in: context)
                order += 1
                created.append(task)
                if !node.children.isEmpty {
                    _ = build(node.children, parent: task, startingAt: 0)
                }
            }
            return created
        }

        let roots = build(outline, parent: parent, startingAt: nextSortOrder)
        nextSortOrder += roots.count
        return roots
    }

    /// Creates **one** task row, applying the same inheritance as a whole breakdown. The row editor's
    /// **+** and Enter-continuation both land here, so project/assignee/triage inheritance is defined once
    /// and cannot drift between the batch path and the row path.
    @discardableResult
    static func makeRow(summary: String = "",
                        under parent: Task?,
                        project: Project? = nil,
                        assignee: Person? = nil,
                        inheritTriageFrom parentNeedsTriage: Bool? = nil,
                        sortOrder: Int,
                        in context: ModelContext) -> Task {
        let task = Task(summary: summary)
        context.insert(task)
        task.parent = parent
        task.project = project ?? parent?.project
        task.assignee = assignee ?? parent?.assignee
        task.sortOrder = sortOrder
        // A breakdown of reviewed work is reviewed; a parentless row is fresh capture and stays in the Inbox.
        let needsTriage = parentNeedsTriage ?? parent?.needsTriage ?? true
        if !needsTriage { task.markReviewed() }
        return task
    }

    /// Convenience: parse `text` and create it in one step. Returns the new root tasks (empty if the
    /// text held nothing usable).
    @discardableResult
    static func create(text: String,
                       under parent: Task?,
                       project: Project? = nil,
                       assignee: Person? = nil,
                       in context: ModelContext) -> [Task] {
        create(TaskOutlineParser.parse(text), under: parent, project: project,
               assignee: assignee, in: context)
    }
}
