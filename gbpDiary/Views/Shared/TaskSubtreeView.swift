import SwiftUI
import SwiftData

// Renders a list of tasks (with their subtrees) for any container context:
// diary subtasks, meeting task lists, project/person/institution task lists.
//
// Callers provide the root tasks (parent == nil within that container) and
// context-specific callbacks. Children are rendered recursively via childrenSection.
struct TaskSubtreeView: View {
    var tasks: [Task]
    var collapsedIds: Binding<Set<UUID>>
    var defaultDate: Date = Date()
    var onEdit: (Task) -> Void
    // Reorder root tasks within this container. Receives updated sortOrder values.
    var onReorder: ((Task, Int) -> Void)?
    // Make `dragged` a subtask of `target`.
    var onMakeSubtask: ((Task, Task) -> Void)?
    // Detach task from parent and promote to root of this container.
    var onPromote: ((Task) -> Void)?
    // Remove task from this container entirely (e.g., meeting → diary).
    var onRemove: ((Task) -> Void)?
    // Delete task from the model context.
    var onDelete: (Task) -> Void
    // Handle a drop of an external UUID (e.g., from diary drop zone into meeting).
    var onDropExternal: ((String) -> Bool)?
    // Handle a drop of an external UUID onto a specific task label (make it a subtask).
    var onDropExternalOntoTask: ((String, Task) -> Bool)? = nil

    @Environment(\.modelContext) private var modelContext
    @FocusState private var focusedTaskId: UUID?
    @State private var activeDropZone: Int?
    @State private var dropTargetId: UUID?
    @State private var editingTask: Task?

    private static let indentStep: CGFloat = 16

    // Defensive filter: exclude tasks whose parent is also in the provided tasks list.
    // Guards against SwiftData's deferred inverse-relationship updates causing momentary
    // duplicates when a sibling is reparented onto another sibling.
    private var sortedRoots: [Task] {
        let ids = Set(tasks.map(\.id))
        return tasks
            .filter { t in t.parent == nil || !ids.contains(t.parent!.id) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    // Find any task in the subtree (including children and deeper descendants).
    private func findDescendant(id: UUID) -> Task? {
        func search(_ list: [Task]) -> Task? {
            for t in list {
                if t.id == id { return t }
                if let found = search(t.children) { return found }
            }
            return nil
        }
        return search(sortedRoots)
    }

    private func isDescendant(_ potentialDescendant: Task, of ancestor: Task) -> Bool {
        var current: Task? = potentialDescendant.parent
        while let c = current {
            if c.id == ancestor.id { return true }
            current = c.parent
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dropZone(at: 0)
            ForEach(Array(sortedRoots.enumerated()), id: \.element.id) { idx, task in
                taskGroup(task, rootIndex: idx)
                dropZone(at: idx + 1)
            }
        }
        .sheet(item: $editingTask) { task in
            TaskEditorSheet(task: task, defaultDate: defaultDate)
        }
    }

    @ViewBuilder
    private func taskNotesArea(for task: Task) -> some View {
        let hasNotes = !(task.notes ?? "").isEmpty
        let isNotesFocused = focusedTaskId == task.notesAreaFocusId
        if (hasNotes || isNotesFocused) && !collapsedIds.wrappedValue.contains(task.id) {
            EntryNotesSubArea(
                text: Binding(
                    get: { task.notes ?? "" },
                    set: { task.notes = $0.isEmpty ? nil : $0 }
                ),
                isFocused: isNotesFocused,
                focusedEntryId: $focusedTaskId,
                focusId: task.notesAreaFocusId,
                placeholder: "Add notes…",
                onMoveToPrevious: nil,
                onMoveToNext: nil
            )
            .padding(.leading, 8)
            .padding(.trailing, 8)
            .padding(.bottom, 4)
        }
    }

    @ViewBuilder
    private func taskGroup(_ task: Task, rootIndex: Int) -> some View {
        taskRow(task)
            .draggable(task.id.uuidString)
        taskNotesArea(for: task)
        if !collapsedIds.wrappedValue.contains(task.id), !task.children.isEmpty {
            childrenSection(of: task)
        }
    }

    // Recursively renders a "Subtasks" section for a task's children.
    // AnyView at the recursive call site breaks Swift's opaque-return-type cycle.
    private func childrenSection(of parent: Task) -> AnyView {
        let children = parent.children.sorted { $0.sortOrder < $1.sortOrder }
        let view = VStack(alignment: .leading, spacing: 0) {
            Text("Subtasks")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 2)
            ForEach(children) { child in
                taskRow(child)
                    .draggable(child.id.uuidString)
                taskNotesArea(for: child)
                if !collapsedIds.wrappedValue.contains(child.id), !child.children.isEmpty {
                    childrenSection(of: child)
                }
            }
            .padding(.bottom, 2)
        }
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        .padding(.leading, Self.indentStep)
        .padding(.trailing, 8)
        .padding(.bottom, 4)
        return AnyView(view)
    }

    private func taskRow(_ task: Task) -> some View {
        HStack(spacing: 4) {
            if task.needsChevron {
                Button {
                    if collapsedIds.wrappedValue.contains(task.id) {
                        collapsedIds.wrappedValue.remove(task.id)
                    } else {
                        collapsedIds.wrappedValue.insert(task.id)
                    }
                } label: {
                    Image(systemName: collapsedIds.wrappedValue.contains(task.id) ? "chevron.right" : "chevron.down")
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
                    if let onMakeSubtask,
                       let dragged = findDescendant(id: id) ?? sortedRoots.first(where: { $0.id == id }),
                       !isDescendant(task, of: dragged) {
                        onMakeSubtask(dragged, task)
                        return true
                    }
                    return onDropExternalOntoTask?(uuidString, task) ?? false
                } isTargeted: { dropTargetId = $0 ? task.id : nil }
                .overlay {
                    if dropTargetId == task.id {
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.accentColor, lineWidth: 1.5)
                            .allowsHitTesting(false)
                    }
                }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .contextMenu {
            Button("Edit Task") { editingTask = task }
            Divider()
            if task.parent != nil {
                Button("Detach from Parent") { onPromote?(task) }
            } else if let onRemove {
                Button("Remove from Here") { onRemove(task) }
            }
            Button("Delete Task", role: .destructive) { onDelete(task) }
        }
    }

    private func dropZone(at index: Int) -> some View {
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
            // Root-level drag → reorder
            if let dragged = sortedRoots.first(where: { $0.id == id }) {
                reorderRoot(dragged, toIndex: index)
                activeDropZone = nil
                return true
            }
            // Child drag → promote then reorder
            if let dragged = findDescendant(id: id) {
                onPromote?(dragged)
                reorderRoot(dragged, toIndex: index)
                activeDropZone = nil
                return true
            }
            // External UUID
            if let handler = onDropExternal {
                let handled = handler(uuidString)
                if handled { activeDropZone = nil }
                return handled
            }
            return false
        } isTargeted: { targeted in
            activeDropZone = targeted ? index : nil
        }
    }

    private func reorderRoot(_ dragged: Task, toIndex dropIndex: Int) {
        var sorted = sortedRoots
        guard let fromIndex = sorted.firstIndex(where: { $0.id == dragged.id }) else {
            dragged.sortOrder = (sorted.map(\.sortOrder).max() ?? -1) + 1
            onReorder?(dragged, dragged.sortOrder)
            return
        }
        sorted.remove(at: fromIndex)
        let target = min(dropIndex > fromIndex ? dropIndex - 1 : dropIndex, sorted.count)
        sorted.insert(dragged, at: target)
        for (i, task) in sorted.enumerated() {
            task.sortOrder = i
            onReorder?(task, i)
        }
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
