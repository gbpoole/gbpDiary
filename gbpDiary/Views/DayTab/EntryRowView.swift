import SwiftUI
import SwiftData

struct EntryRowView: View {
    @Bindable var entry: DayEntry
    var focusedEntryId: FocusState<UUID?>.Binding
    var onMoveToPrevious: (() -> Void)? = nil
    var onMoveToNext: (() -> Void)? = nil
    var onDeleteEmpty: (() -> Void)? = nil
    var hasChildren: Bool = false
    var isCollapsed: Bool = false
    var onToggleCollapse: (() -> Void)? = nil
    var isNotesFocused: Bool = false
    var onMoveToNextFromNotes: (() -> Void)? = nil
    var onDropDiaryEntry: ((String) -> Bool)? = nil
    var onDropOntoEntry: ((String) -> Bool)? = nil
    var onRemoveFromMeeting: ((Task) -> Void)? = nil
    var onDropExternalOntoMeetingTask: ((String, Task) -> Bool)? = nil

    @Environment(\.modelContext) private var modelContext
    @State private var editingMinutes: Minutes?
    @State private var showingDeleteConfirm = false
    @State private var isDropTargeted = false
    @State private var meetingTaskCollapsedIds: Set<UUID> = []

    private var isEntryFocused: Bool { focusedEntryId.wrappedValue == entry.id }

    private static let indentStep: CGFloat = 20

    var body: some View {
        Group {
            switch entry.kind {
            case .note, .task: EmptyView()
            case .meeting: meetingRow
            }
        }
        .padding(.leading, CGFloat(entry.indentLevel) * Self.indentStep)
        .overlay(alignment: .topLeading) {
            if hasChildren {
                Button { onToggleCollapse?() } label: {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 20, height: 28)
                .contentShape(Rectangle())
                .padding(.leading, max(0, CGFloat(entry.indentLevel) * Self.indentStep - 14))
            }
        }
        .alert("Delete Meeting?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let m = entry.minutes { modelContext.delete(m) }
                modelContext.delete(entry)
            }
        } message: {
            Text("This will also delete the associated meeting notes.")
        }
    }

    // MARK: - Meeting

    private var meetingRow: some View {
        let notesText = entry.minutes?.minutesContent ?? ""
        let showNotes = (!notesText.isEmpty || isEntryFocused || isNotesFocused) && !isCollapsed
        let rootTasks = !isCollapsed
            ? (entry.minutes?.newTasks ?? []).filter { $0.parent == nil }.sorted { $0.sortOrder < $1.sortOrder }
            : []
        let hasTasks = !rootTasks.isEmpty
        let nextForSummary: (() -> Void)? = showNotes
            ? { focusedEntryId.wrappedValue = entry.notesAreaFocusId }
            : hasTasks
                ? { if let first = rootTasks.first { focusedEntryId.wrappedValue = first.id } else { onMoveToNext?() } }
                : onMoveToNext
        let summaryBinding = Binding<String>(
            get: { entry.inlineSummary },
            set: { entry.inlineSummary = $0 }
        )
        return VStack(alignment: .leading, spacing: 0) {
            MeetingEntryContent(
                summaryBinding: summaryBinding,
                minutes: entry.minutes,
                isEntryFocused: isEntryFocused,
                onEdit: { minutes in editingMinutes = minutes },
                inlineText: { binding in
                    InlineEditableSingleLineText(
                        placeholder: "Meeting summary",
                        text: binding,
                        isFocused: isEntryFocused,
                        focusBinding: focusedEntryId,
                        focusId: entry.id,
                        onIndent: nil,
                        onOutdent: nil,
                        onMoveToPrevious: onMoveToPrevious,
                        onMoveToNext: nextForSummary
                    )
                }
            )
            .contextMenu { deleteButton }
            .modifier(RowCardStyling(verticalPadding: 2))
            .draggable(entry.id.uuidString)
            .sheet(item: $editingMinutes) { m in MinutesDetailView(minutes: m, asSheet: true) }
            .dropDestination(for: String.self) { items, _ in
                guard let str = items.first else { return false }
                return onDropOntoEntry?(str) ?? false
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
            if showNotes, let minutes = entry.minutes {
                EntryNotesSubArea(
                    text: Binding(
                        get: { minutes.minutesContent ?? "" },
                        set: { minutes.minutesContent = $0.isEmpty ? nil : $0 }
                    ),
                    isFocused: isNotesFocused,
                    focusedEntryId: focusedEntryId,
                    focusId: entry.notesAreaFocusId,
                    placeholder: "Add meeting minutes…",
                    onMoveToPrevious: { focusedEntryId.wrappedValue = entry.id },
                    onMoveToNext: hasTasks
                        ? { if let first = rootTasks.first { focusedEntryId.wrappedValue = first.id } else { onMoveToNextFromNotes?() } }
                        : onMoveToNextFromNotes
                )
                .padding(.leading, Self.indentStep)
                .padding(.horizontal)
                .padding(.bottom, 4)
            }
            if !isCollapsed, let minutes = entry.minutes,
               !minutes.newTasks.filter({ $0.parent == nil }).isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("New Tasks")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.top, 6)
                        .padding(.bottom, 2)
                    TaskSubtreeView(
                        tasks: minutes.newTasks.filter { $0.parent == nil },
                        collapsedIds: $meetingTaskCollapsedIds,
                        focusedId: focusedEntryId,
                        defaultDate: minutes.meetingAt,
                        onEdit: { _ in },
                        onReorder: { task, i in task.sortOrder = i },
                        onMakeSubtask: { dragged, target in dragged.parent = target },
                        onPromote: { task in task.parent = nil },
                        onRemove: onRemoveFromMeeting,
                        onDelete: { task in
                            task.originMinutes = nil
                            task.parent = nil
                            modelContext.delete(task)
                        },
                        onDropExternal: onDropDiaryEntry,
                        onDropExternalOntoTask: onDropExternalOntoMeetingTask,
                        onNavigatePrev: {
                            if showNotes {
                                focusedEntryId.wrappedValue = entry.notesAreaFocusId
                            } else {
                                focusedEntryId.wrappedValue = entry.id
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
    }

    // MARK: - Shared

    private var deleteButton: some View {
        Button("Delete", role: .destructive) {
            if entry.minutes != nil {
                showingDeleteConfirm = true
            } else {
                modelContext.delete(entry)
            }
        }
    }
}
