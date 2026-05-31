import SwiftUI
import SwiftData

struct MeetingTaskListView: View {
    @Bindable var minutes: Minutes
    var onDropDiaryEntry: ((String) -> Bool)? = nil
    var onRemoveFromMeeting: ((Task) -> Void)? = nil
    @Environment(\.modelContext) private var modelContext
    @State private var activeDropZone: Int?
    @State private var editingTask: Task?
    @State private var collapsedIds: Set<UUID> = []
    @State private var dropTargetId: UUID?

    private static let indentStep: CGFloat = 16

    // Top-level tasks only — children appear via Task.children rendering.
    private var sortedTasks: [Task] {
        minutes.newTasks
            .filter { $0.parent == nil }
            .sorted { $0.meetingTaskSortOrder < $1.meetingTaskSortOrder }
    }

    // Returns true if potentialDescendant is a descendant of ancestor.
    private func isDescendant(_ potentialDescendant: Task, of ancestor: Task) -> Bool {
        var current: Task? = potentialDescendant.parent
        while let c = current {
            if c.id == ancestor.id { return true }
            current = c.parent
        }
        return false
    }

    // Searches the full meeting task tree for a task by UUID.
    private func findDescendantTask(id: UUID) -> Task? {
        func search(_ tasks: [Task]) -> Task? {
            for task in tasks {
                if task.id == id { return task }
                if let found = search(task.children) { return found }
            }
            return nil
        }
        return search(sortedTasks)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New Tasks")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 2)

            taskDropZone(at: 0)
            ForEach(Array(sortedTasks.enumerated()), id: \.element.id) { topIndex, topTask in
                taskGroup(topTask, topIndex: topIndex)
                taskDropZone(at: topIndex + 1)
            }
        }
        .padding(.bottom, 4)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        .sheet(item: $editingTask) { task in
            TaskEditorSheet(task: task, defaultDate: minutes.meetingAt)
        }
    }

    @ViewBuilder
    private func taskGroup(_ task: Task, topIndex: Int) -> some View {
        taskRow(task, depth: 0)
            .draggable(task.id.uuidString)
        if !collapsedIds.contains(task.id) {
            ForEach(task.children.sorted { $0.createdAt < $1.createdAt }) { child in
                taskRow(child, depth: 1)
                    .draggable(child.id.uuidString)
                // Grandchildren shown one level deeper (no further nesting in UI for now)
                if !collapsedIds.contains(child.id) {
                    ForEach(child.children.sorted { $0.createdAt < $1.createdAt }) { grandchild in
                        taskRow(grandchild, depth: 2)
                            .draggable(grandchild.id.uuidString)
                    }
                }
            }
        }
    }

    private func taskRow(_ task: Task, depth: Int) -> some View {
        HStack(spacing: 4) {
            if depth > 0 {
                Color.clear.frame(width: CGFloat(depth) * Self.indentStep)
            }
            let hasChildren = !task.children.isEmpty
            if hasChildren {
                Button {
                    if collapsedIds.contains(task.id) { collapsedIds.remove(task.id) }
                    else { collapsedIds.insert(task.id) }
                } label: {
                    Image(systemName: collapsedIds.contains(task.id) ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 14, height: 20)
            } else {
                Color.clear.frame(width: 14, height: 20)
            }
            Button { cycleStatus(task) } label: {
                Image(systemName: statusIcon(task.status))
                    .foregroundStyle(statusColor(task.status))
                    .font(.system(size: 15))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)

            // Drop-on-task target confined to the label area so it doesn't compete
            // geometrically with the between-group drop zones.
            Text(task.summary.isEmpty ? "(untitled)" : task.summary)
                .lineLimit(1)
                .strikethrough(task.status == .completed || task.status == .cancelled)
                .foregroundStyle(task.status == .cancelled ? Color.secondary : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { editingTask = task }
                .dropDestination(for: String.self) { items, _ in
                    guard let uuidString = items.first,
                          let id = UUID(uuidString: uuidString),
                          id != task.id
                    else { return false }
                    guard let dragged = findDescendantTask(id: id) ?? sortedTasks.first(where: { $0.id == id }),
                          !isDescendant(task, of: dragged)
                    else { return false }
                    dragged.parent = task
                    return true
                } isTargeted: { dropTargetId = $0 ? task.id : nil }
                .overlay {
                    if dropTargetId == task.id {
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.accentColor, lineWidth: 1.5)
                            .allowsHitTesting(false)
                    }
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .contextMenu {
            Button("Edit Task") { editingTask = task }
            Divider()
            if task.parent != nil {
                Button("Detach from Parent") {
                    task.parent = nil
                    task.meetingTaskSortOrder = (sortedTasks.map(\.meetingTaskSortOrder).max() ?? -1) + 1
                }
            } else {
                Button("Remove from Meeting") { onRemoveFromMeeting?(task) }
            }
            Button("Delete Task", role: .destructive) {
                task.originMinutes = nil
                task.parent = nil
                modelContext.delete(task)
            }
        }
    }

    private func taskDropZone(at index: Int) -> some View {
        ZStack {
            Color.clear.frame(height: 4)
            if activeDropZone == index {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .padding(.horizontal, 8)
            }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let uuidString = items.first,
                  let id = UUID(uuidString: uuidString)
            else { return false }
            if let dragged = sortedTasks.first(where: { $0.id == id }) {
                moveTask(dragged, toDropIndex: index)
                activeDropZone = nil
                return true
            }
            // Child task dragged to a drop zone — promote to top-level then reorder
            if let dragged = findDescendantTask(id: id) {
                dragged.parent = nil
                moveTask(dragged, toDropIndex: index)
                activeDropZone = nil
                return true
            }
            if let handler = onDropDiaryEntry { return handler(uuidString) }
            return false
        } isTargeted: { targeted in
            activeDropZone = targeted ? index : nil
        }
    }

    private func moveTask(_ dragged: Task, toDropIndex dropIndex: Int) {
        dragged.originMinutes = minutes
        var sorted = minutes.newTasks
            .filter { $0.parent == nil }
            .sorted { $0.meetingTaskSortOrder < $1.meetingTaskSortOrder }
        guard let fromIndex = sorted.firstIndex(where: { $0.id == dragged.id }) else {
            dragged.meetingTaskSortOrder = (sorted.map(\.meetingTaskSortOrder).max() ?? -1) + 1
            return
        }
        sorted.remove(at: fromIndex)
        let target = min(dropIndex > fromIndex ? dropIndex - 1 : dropIndex, sorted.count)
        sorted.insert(dragged, at: target)
        for (i, task) in sorted.enumerated() { task.meetingTaskSortOrder = i }
    }

    private func cycleStatus(_ task: Task) {
        switch task.status {
        case .todo:      task.status = .started
        case .started:   task.markCompleted()
        case .completed: task.unmarkCompleted()
        default:         break
        }
    }

    private func statusIcon(_ status: TaskStatus) -> String {
        switch status {
        case .todo:            "circle"
        case .started:         "play.circle.fill"
        case .completed:       "checkmark.circle.fill"
        case .cancelled:       "xmark.circle.fill"
        case .followUpPending: "arrow.clockwise.circle.fill"
        }
    }

    private func statusColor(_ status: TaskStatus) -> Color {
        switch status {
        case .todo:            .secondary
        case .started:         .blue
        case .completed:       .green
        case .cancelled:       .secondary
        case .followUpPending: .orange
        }
    }
}
