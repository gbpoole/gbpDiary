import SwiftUI

struct TaskEntryContent: View {
    let task: Task?
    let focusedEntryId: FocusState<UUID?>.Binding
    let focusId: UUID
    let onEdit: (Task) -> Void
    let onMoveToPrevious: (() -> Void)?
    let onMoveToNext: (() -> Void)?
    let onIndent: (() -> Void)?
    let onOutdent: (() -> Void)?
    var isCollapsed: Bool = false
    var onToggleCollapse: (() -> Void)? = nil
    var onBeforeStatusChange: (() -> Void)? = nil

    var body: some View {
        if let task {
            TaskRowView(
                task: task,
                onEdit: { onEdit(task) },
                inlineEditing: true,
                focusBinding: focusedEntryId,
                focusId: focusId,
                onMoveToPrevious: onMoveToPrevious,
                onMoveToNext: onMoveToNext,
                onIndent: onIndent,
                onOutdent: onOutdent,
                isCollapsed: isCollapsed,
                onToggleCollapse: onToggleCollapse,
                onBeforeStatusChange: onBeforeStatusChange
            )
        } else {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                Text("(missing task)").foregroundStyle(.tertiary)
            }
            .padding(.horizontal)
            .padding(.vertical, 5)
        }
    }
}
