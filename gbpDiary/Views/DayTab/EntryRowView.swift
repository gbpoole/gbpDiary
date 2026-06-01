import SwiftUI
import SwiftData
import Textual

struct EntryRowView: View {
    @Bindable var entry: DayEntry
    var focusedEntryId: FocusState<UUID?>.Binding
    var onAddNoteAfter: (() -> Void)? = nil
    var onMoveToPrevious: (() -> Void)? = nil
    var onMoveToNext: (() -> Void)? = nil
    var onDeleteEmpty: (() -> Void)? = nil
    var onIndent: (() -> Void)? = nil
    var onOutdent: (() -> Void)? = nil
    var hasChildren: Bool = false
    var isCollapsed: Bool = false
    var onToggleCollapse: (() -> Void)? = nil
    var onSplitNote: (() -> Void)? = nil
    var isNotesFocused: Bool = false
    var onMoveToNextFromNotes: (() -> Void)? = nil
    var onDropDiaryEntry: ((String) -> Bool)? = nil
    var onDropOntoEntry: ((String) -> Bool)? = nil
    var onRemoveFromMeeting: ((Task) -> Void)? = nil
    var onDropExternalOntoMeetingTask: ((String, Task) -> Bool)? = nil

    @Environment(\.modelContext) private var modelContext
    @State private var editingTask: Task?
    @State private var editingMinutes: Minutes?
    @State private var showingDeleteConfirm = false
    @State private var isDropTargeted = false
    @State private var meetingTaskCollapsedIds: Set<UUID> = []

    private var isEntryFocused: Bool { focusedEntryId.wrappedValue == entry.id }

    private static let indentStep: CGFloat = 20

    var body: some View {
        Group {
            switch entry.kind {
            case .note:    noteRow
            case .task:    taskRow
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

    private func indent() {
        if let handler = onIndent { handler() } else { entry.indentLevel = min(entry.indentLevel + 1, 6) }
    }

    private func outdent() {
        if let handler = onOutdent { handler() } else { entry.indentLevel = max(entry.indentLevel - 1, 0) }
    }

    // MARK: - Visual line helpers (note row only)

    // Inspect the focused NSTextView's layout manager to determine whether the
    // insertion point sits on the topmost or bottommost visual line. Used to
    // decide whether an arrow key should move between entries or stay within
    // the multi-line note text. Defaults to true (navigate between entries) on
    // any platform or state where the check isn't possible.
#if os(macOS)
    private var cursorIsOnFirstVisualLine: Bool {
        guard let tv = NSApp.keyWindow?.firstResponder as? NSTextView,
              let lm = tv.layoutManager,
              lm.numberOfGlyphs > 0 else { return true }
        let pos = min(tv.selectedRange().location, tv.string.utf16.count)
        let glyph = min(lm.glyphIndexForCharacter(at: pos), lm.numberOfGlyphs - 1)
        let curY = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
        let topY = lm.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).minY
        return curY <= topY + 1
    }

    private var cursorIsOnLastVisualLine: Bool {
        guard let tv = NSApp.keyWindow?.firstResponder as? NSTextView,
              let lm = tv.layoutManager,
              lm.numberOfGlyphs > 0 else { return true }
        let sel = tv.selectedRange()
        let pos = min(sel.location + sel.length, tv.string.utf16.count)
        let glyph = min(lm.glyphIndexForCharacter(at: pos), lm.numberOfGlyphs - 1)
        let curY = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
        let botY = lm.lineFragmentRect(forGlyphAt: lm.numberOfGlyphs - 1, effectiveRange: nil).minY
        return curY >= botY - 1
    }
#endif

    // MARK: - Note

    private var noteRow: some View {
        NoteEntryContent(
            text: $entry.text,
            isFocused: isEntryFocused,
            focusedEntryId: focusedEntryId,
            focusId: entry.id,
            onIndent: indent,
            onOutdent: outdent,
            onMoveToPrevious: onMoveToPrevious,
            onMoveToNext: onMoveToNext,
            allowMoveToPrevious: {
                #if os(macOS)
                return cursorIsOnFirstVisualLine
                #else
                return true
                #endif
            },
            allowMoveToNext: {
                #if os(macOS)
                return cursorIsOnLastVisualLine
                #else
                return true
                #endif
            },
            onSplit: onSplitNote
        )
        .padding(8)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal)
        .padding(.vertical, 4)
        .contextMenu {
            deleteButton
            #if os(macOS)
            if isEntryFocused, onSplitNote != nil {
                Divider()
                Button("Split Note Here") { onSplitNote?() }
            }
            #endif
        }
    }

    // MARK: - Task

    private var taskRow: some View {
        let notesText = entry.task?.notes ?? ""
        let showNotes = (!notesText.isEmpty || isEntryFocused || isNotesFocused) && !isCollapsed
        return VStack(alignment: .leading, spacing: 0) {
            rowCard(verticalPadding: 2) {
                TaskEntryContent(
                    task: entry.task,
                    focusedEntryId: focusedEntryId,
                    focusId: entry.id,
                    onEdit: { task in editingTask = task },
                    onMoveToPrevious: onMoveToPrevious,
                    onMoveToNext: showNotes
                        ? { focusedEntryId.wrappedValue = entry.notesAreaFocusId }
                        : onMoveToNext,
                    onIndent: onIndent,
                    onOutdent: onOutdent
                )
            }
            .contextMenu { deleteButton }
            .sheet(item: $editingTask) { task in
                TaskEditorSheet(task: task, defaultDate: entry.createdAt)
            }
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
            if showNotes, let task = entry.task {
                EntryNotesSubArea(
                    text: Binding(
                        get: { task.notes ?? "" },
                        set: { task.notes = $0.isEmpty ? nil : $0 }
                    ),
                    isFocused: isNotesFocused,
                    focusedEntryId: focusedEntryId,
                    focusId: entry.notesAreaFocusId,
                    placeholder: "Add task notes…",
                    onMoveToPrevious: { focusedEntryId.wrappedValue = entry.id },
                    onMoveToNext: onMoveToNextFromNotes
                )
                .padding(.leading, Self.indentStep)
                .padding(.horizontal)
                .padding(.bottom, 4)
            }
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
                        onIndent: indent,
                        onOutdent: outdent,
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
            if entry.kind == .meeting && entry.minutes != nil {
                showingDeleteConfirm = true
            } else {
                modelContext.delete(entry)
            }
        }
    }

    private func rowCard<Content: View>(
        verticalPadding: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .modifier(RowCardStyling(verticalPadding: verticalPadding))
    }
}
