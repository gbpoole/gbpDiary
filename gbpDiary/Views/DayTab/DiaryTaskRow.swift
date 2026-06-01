import SwiftUI
import SwiftData

// Renders a root diary task (Task with dayRecord set) with inline editing,
// notes sub-area, collapse/expand chevron, and an inline subtask tree.
struct DiaryTaskRow: View {
    @Bindable var task: Task
    var focusedEntryId: FocusState<UUID?>.Binding
    var isCollapsed: Bool = false
    var onToggleCollapse: (() -> Void)? = nil
    var onMoveToPrevious: (() -> Void)? = nil
    var onMoveToNext: (() -> Void)? = nil
    var onMoveToNextFromNotes: (() -> Void)? = nil
    var onIndent: (() -> Void)? = nil
    var onOutdent: (() -> Void)? = nil
    var onDropOntoTask: ((String) -> Bool)? = nil
    var onExternalDropOntoSubtask: ((String, Task) -> Bool)? = nil
    var onExternalDropIntoSubtree: ((String) -> Bool)? = nil

    @Environment(\.modelContext) private var modelContext
    @State private var editingTask: Task?
    @State private var isDropTargeted = false
    @State private var subtreeCollapsedIds: Set<UUID> = []

    private static let indentStep: CGFloat = 20

    private var isEntryFocused: Bool { focusedEntryId.wrappedValue == task.id }
    private var isNotesFocused: Bool { focusedEntryId.wrappedValue == task.notesAreaFocusId }

    private var showNotes: Bool {
        let text = task.notes ?? ""
        return (!text.isEmpty || isEntryFocused || isNotesFocused) && !isCollapsed
    }

    private var showChildren: Bool {
        !task.children.isEmpty && !isCollapsed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowCard
            if showNotes {
                notesArea
            }
            if showChildren {
                subtreeArea
            }
        }
        .overlay(alignment: .topLeading) {
            if task.needsChevron {
                Button { onToggleCollapse?() } label: {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 20, height: 28)
                .contentShape(Rectangle())
            }
        }
        .sheet(item: $editingTask) { t in
            TaskEditorSheet(task: t, defaultDate: task.dayRecord?.date ?? Date())
        }
    }

    private var rowCard: some View {
        TaskEntryContent(
            task: task,
            focusedEntryId: focusedEntryId,
            focusId: task.id,
            onEdit: { t in editingTask = t },
            onMoveToPrevious: onMoveToPrevious,
            onMoveToNext: showNotes
                ? { focusedEntryId.wrappedValue = task.notesAreaFocusId }
                : showChildren
                    ? { if let first = task.children.sorted(by: { $0.sortOrder < $1.sortOrder }).first {
                            focusedEntryId.wrappedValue = first.id
                        } else { onMoveToNext?() } }
                    : onMoveToNext,
            onIndent: onIndent,
            onOutdent: onOutdent
        )
        .modifier(RowCardStyling(verticalPadding: 2))
        .draggable(task.id.uuidString)
        .contextMenu {
            Button("Delete", role: .destructive) { modelContext.delete(task) }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let str = items.first else { return false }
            return onDropOntoTask?(str) ?? false
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .padding(.horizontal)
                    .padding(.vertical, 2)
                    .allowsHitTesting(false)
            }
        }
    }

    private var notesArea: some View {
        EntryNotesSubArea(
            text: Binding(
                get: { task.notes ?? "" },
                set: { task.notes = $0.isEmpty ? nil : $0 }
            ),
            isFocused: isNotesFocused,
            focusedEntryId: focusedEntryId,
            focusId: task.notesAreaFocusId,
            placeholder: "Add task notes…",
            onMoveToPrevious: { focusedEntryId.wrappedValue = task.id },
            onMoveToNext: showChildren
                ? { if let first = task.children.sorted(by: { $0.sortOrder < $1.sortOrder }).first {
                        focusedEntryId.wrappedValue = first.id
                    } else { onMoveToNextFromNotes?() } }
                : onMoveToNextFromNotes
        )
        .padding(.leading, Self.indentStep)
        .padding(.horizontal)
        .padding(.bottom, 4)
    }

    private var subtreeArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Subtasks")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 2)

            TaskSubtreeView(
                tasks: task.children,
                collapsedIds: $subtreeCollapsedIds,
                focusedId: focusedEntryId,
                defaultDate: task.dayRecord?.date ?? Date(),
                onEdit: { editingTask = $0 },
                onMakeSubtask: { dragged, target in
                    dragged.parent = target
                    dragged.dayRecord = nil
                    dragged.originMinutes = nil
                },
                onPromote: { [task] child in
                    child.parent = task
                    child.dayRecord = nil
                    child.originMinutes = nil
                },
                onDelete: { modelContext.delete($0) },
                onDropExternal: onExternalDropIntoSubtree,
                onDropExternalOntoTask: onExternalDropOntoSubtask,
                onNavigatePrev: {
                    let hasNotes = !(task.notes ?? "").isEmpty
                    if hasNotes {
                        focusedEntryId.wrappedValue = task.notesAreaFocusId
                    } else {
                        focusedEntryId.wrappedValue = task.id
                    }
                },
                onNavigateNext: onMoveToNextFromNotes
            )
            .padding(.bottom, 4)
        }
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        .padding(.leading, Self.indentStep)
        .padding(.horizontal)
        .padding(.bottom, 4)
    }
}
