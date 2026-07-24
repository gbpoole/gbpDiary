import SwiftUI
import SwiftData

struct EntryRowView: View {
    @Bindable var entry: DayEntry
    var focusedEntryId: FocusState<UUID?>.Binding
    var onMoveToPrevious: (() -> Void)? = nil
    var onMoveToNext: (() -> Void)? = nil
    var onDeleteEmpty: (() -> Void)? = nil
    var isCollapsed: Bool = false
    var onToggleCollapse: (() -> Void)? = nil
    var onDropDiaryEntry: ((String) -> Bool)? = nil
    var onDropOntoEntry: ((String) -> Bool)? = nil
    var onRemoveFromMeeting: ((Task) -> Void)? = nil
    var onDropExternalOntoMeetingTask: ((String, Task) -> Bool)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(MinutesEditorContext.self) private var editorContext
    @State private var editingMinutes: Minutes?
    @State private var showingDeleteConfirm = false
    @State private var summaryDraft = ""
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
        .alert("Delete Meeting?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let m = entry.minutes {
                    if let note = m.note { editorContext.remove(note: note) }
                    modelContext.delete(m)
                }
                modelContext.delete(entry)
            }
        } message: {
            Text("This will also delete the associated meeting notes.")
        }
    }

    // MARK: - Meeting

    private var meetingRow: some View {
        let showNotes = entry.minutes?.note != nil && !isCollapsed
        let rootTasks = !isCollapsed
            ? (entry.minutes?.newTasks ?? []).filter { $0.parent == nil }.sorted { $0.sortOrder < $1.sortOrder }
            : []
        let hasTasks = !rootTasks.isEmpty
        let nextForSummary: (() -> Void)? = hasTasks
            ? { if let first = rootTasks.first { focusedEntryId.wrappedValue = first.id } else { onMoveToNext?() } }
            : onMoveToNext
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                Group {
                    if let toggle = onToggleCollapse {
                        Button(action: toggle) {
                            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 20, height: 28)
                MeetingEntryContent(
                    summaryBinding: $summaryDraft,
                    minutes: entry.minutes,
                    isEntryFocused: isEntryFocused,
                    isCollapsed: isCollapsed,
                    onToggleCollapse: nil,
                    onAddMinutes: {
                        guard let m = entry.minutes else { return }
                        let note = Note(content: "")
                        modelContext.insert(note)
                        m.note = note
                        m.updatedAt = Date()
                        editorContext.open(note: note, title: m.summary ?? "Meeting")
                    },
                    onOpenMinutes: {
                        guard let note = entry.minutes?.note else { return }
                        editorContext.open(note: note, title: entry.minutes?.summary ?? "Meeting")
                    },
                    onEdit: { minutes in editingMinutes = minutes },
                    onDelete: { showingDeleteConfirm = true },
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
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    if isDropTargeted {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.accentColor, lineWidth: 2)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.trailing)
                .sheet(item: $editingMinutes) { m in MinutesDetailView(minutes: m, asSheet: true).presentationSizing(.fitted) }
                .dropDestination(for: String.self) { items, _ in
                    guard let str = items.first else { return false }
                    return onDropOntoEntry?(str) ?? false
                } isTargeted: { isDropTargeted = $0 }
            }
            .padding(.leading)
            .padding(.vertical, 2)
            .draggable(entry.id.uuidString)
            if showNotes, let minutes = entry.minutes, let note = minutes.note {
                HStack(alignment: .top, spacing: 6) {
                    Color.clear.frame(width: 16)
                    MarkdownDocumentEditor(note: note)
                        .padding(.leading, Self.indentStep)
                }
                .padding(.leading)
                .padding(.trailing)
                .padding(.bottom, 4)
            }
            if !isCollapsed, let minutes = entry.minutes,
               !minutes.newTasks.filter({ $0.parent == nil }).isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Color.clear.frame(width: 16)
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
                            onNavigatePrev: { focusedEntryId.wrappedValue = entry.id },
                            onNavigateNext: onMoveToNext
                        )
                        .padding(.bottom, 4)
                    }
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    .padding(.leading, Self.indentStep)
                }
                .padding(.leading)
                .padding(.trailing)
                .padding(.bottom, 4)
            }
        }
        .onAppear {
            summaryDraft = entry.inlineSummary
            guard let minutes = entry.minutes,
                  minutes.note == nil,
                  let legacy = minutes.minutesContent, !legacy.isEmpty else { return }
            let note = Note(content: legacy)
            modelContext.insert(note)
            minutes.note = note
            minutes.minutesContent = nil
            minutes.updatedAt = Date()
        }
        .onDisappear { entry.inlineSummary = summaryDraft }
        .onChange(of: isEntryFocused) { _, focused in
            if !focused { entry.inlineSummary = summaryDraft }
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
