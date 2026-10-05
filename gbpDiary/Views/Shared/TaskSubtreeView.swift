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
    // Shared focus binding from the parent diary view — allows navigation to cross
    // the subtree boundary into surrounding diary content.
    var focusedId: FocusState<UUID?>.Binding
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
    // Called when ↑ is pressed on the first task (navigate to parent context above).
    var onNavigatePrev: (() -> Void)? = nil
    // Called when ↓ is pressed on the last task (navigate to parent context below).
    var onNavigateNext: (() -> Void)? = nil
    // Row-editing powers (Tab/Shift-Tab depth changes, double-click to the task page). Nil = the subtree
    // renders exactly as it always has, which is how surfaces that haven't adopted it stay unaffected.
    var editing: SubtaskEditing? = nil

    @Environment(\.modelContext) private var modelContext
    @State private var activeDropZone: Int?
    @State private var dropTargetId: UUID?
    @State private var editingTask: Task?
    /// Anchor for ⇧-click range selection — the row the current range grew from.
    @State private var selectionAnchor: UUID?
    /// Set while confirming a delete that would take descendants with it.
    @State private var pendingDelete: SubtaskOutlineEdit.DeletionScope?
    #if os(macOS)
    @State private var keys = SubtaskRowKeyMonitor()
    #endif

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

    // Depth-first list of all tasks currently visible (respects collapse at every level).
    private var flatVisibleTasks: [Task] {
        var result: [Task] = []
        func collect(_ list: [Task]) {
            for t in list.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                result.append(t)
                if !collapsedIds.wrappedValue.contains(t.id) {
                    collect(t.children)
                }
            }
        }
        collect(sortedRoots)
        return result
    }

    // ↑ from `task`: land on the previous task's notes (if visible) or its row, or escape prev.
    private func prevMove(for task: Task) -> (() -> Void)? {
        let flat = flatVisibleTasks
        guard let idx = flat.firstIndex(where: { $0.id == task.id }) else { return onNavigatePrev }
        guard idx > 0 else { return onNavigatePrev }
        let prev = flat[idx - 1]
        return {
            let prevHasNotes = !(prev.notes ?? "").isEmpty
            let prevCollapsed = collapsedIds.wrappedValue.contains(prev.id)
            if prevHasNotes && !prevCollapsed {
                focusedId.wrappedValue = prev.notesAreaFocusId
            } else {
                focusedId.wrappedValue = prev.id
            }
        }
    }

    // ↓ from `task` row: land on its notes (if visible) or next task's row, or escape next.
    private func nextMove(for task: Task) -> (() -> Void)? {
        let flat = flatVisibleTasks
        guard let idx = flat.firstIndex(where: { $0.id == task.id }) else { return onNavigateNext }
        let hasNotes = !(task.notes ?? "").isEmpty
        let isCollapsed = collapsedIds.wrappedValue.contains(task.id)
        if hasNotes && !isCollapsed {
            return { focusedId.wrappedValue = task.notesAreaFocusId }
        }
        guard idx < flat.count - 1 else { return onNavigateNext }
        let next = flat[idx + 1]
        return { focusedId.wrappedValue = next.id }
    }

    // ↓ from `task` notes: land on next task's row, or escape next.
    private func notesNextMove(for task: Task) -> (() -> Void)? {
        let flat = flatVisibleTasks
        guard let idx = flat.firstIndex(where: { $0.id == task.id }) else { return onNavigateNext }
        guard idx < flat.count - 1 else { return onNavigateNext }
        let next = flat[idx + 1]
        return { focusedId.wrappedValue = next.id }
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

    // Every task in the subtree, collapse ignored — restructuring must see rows that aren't on screen.
    private var allTasksInSubtree: [Task] {
        var result: [Task] = []
        func collect(_ list: [Task]) {
            for task in list {
                result.append(task)
                collect(task.children)
            }
        }
        collect(sortedRoots)
        return result
    }

    /// The subtree reduced to what `SubtaskOutlineEdit` needs.
    private var outlineRows: [OutlineRow] {
        allTasksInSubtree.map {
            OutlineRow(id: $0.id, parentID: $0.parent?.id, sortOrder: $0.sortOrder)
        }
    }

    /// Tab: become a child of the preceding sibling, landing at the end of its children — directly below
    /// where the row already sat, so the move reads as an indent rather than a jump.
    private func indentRow(_ task: Task) {
        guard let editing else { return }
        let rows = outlineRows
        guard case .to(let newParentID) = SubtaskOutlineEdit.indent(task.id, in: rows) else { return }
        let all = allTasksInSubtree
        let order = SubtaskOutlineEdit.appendSortOrder(parentID: newParentID, in: rows)
        // A nil id means the container's root; the caller resolves what that is for its surface.
        editing.setParent(task, newParentID.flatMap { id in all.first { $0.id == id } })
        task.sortOrder = order
    }

    /// Shift-Tab: promote to the grandparent, landing immediately after the parent just left.
    private func outdentRow(_ task: Task) {
        guard let editing, let oldParentID = task.parent?.id else { return }
        let rows = outlineRows
        guard case .to(let newParentID) = SubtaskOutlineEdit.outdent(task.id, in: rows,
                                                                    floorParentID: editing.floorParentID)
        else { return }
        let all = allTasksInSubtree
        let placement = SubtaskOutlineEdit.placeAfter(anchorID: oldParentID, parentID: newParentID,
                                                      moving: task.id, in: rows)
        editing.setParent(task, newParentID.flatMap { id in all.first { $0.id == id } })
        task.sortOrder = placement.order
        for (id, order) in placement.shifted {
            all.first { $0.id == id }?.sortOrder = order
        }
    }

    // MARK: - Selection

    private var selectedIDs: Set<UUID> { editing?.selection.wrappedValue ?? [] }

    /// Click selects (⌘ toggles, ⇧ extends from the anchor) — the same model as the board's cards and the
    /// Tasks table, so all three selection surfaces behave alike. Editing starts on Return, not on click.
    private func select(_ task: Task) {
        guard let editing else { return }
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift), let anchor = selectionAnchor {
            let flat = flatVisibleTasks.map(\.id)
            if let from = flat.firstIndex(of: anchor), let to = flat.firstIndex(of: task.id) {
                editing.selection.wrappedValue = Set(flat[min(from, to)...max(from, to)])
                return
            }
        }
        if flags.contains(.command) {
            var next = editing.selection.wrappedValue
            if next.contains(task.id) { next.remove(task.id) } else { next.insert(task.id) }
            editing.selection.wrappedValue = next
        } else {
            editing.selection.wrappedValue = [task.id]
        }
        selectionAnchor = task.id
        // Clicking a row ends any edit in progress elsewhere, flushing its text as it loses focus.
        if focusedId.wrappedValue != nil { focusedId.wrappedValue = nil }
    }

    // MARK: - Row lifecycle

    /// The + button: a new row at the end of the container's top level, focused for typing.
    private func addRow() {
        guard let editing else { return }
        let order = SubtaskOutlineEdit.appendSortOrder(parentID: editing.floorParentID, in: outlineRows)
        guard let row = editing.createRow(nil, order) else { return }
        editing.selection.wrappedValue = [row.id]
        selectionAnchor = row.id
        focusedId.wrappedValue = row.id
    }

    /// Return while editing: commit the text and open the next sibling. An empty row ends the session
    /// instead, taking itself with it (mirroring `MarkdownFormatting.returnInList`).
    private func commitRow(_ task: Task, draft: String) {
        guard let editing else { return }
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            focusedId.wrappedValue = nil
            editing.selection.wrappedValue.remove(task.id)
            dropRow(task)
            return
        }
        task.summary = trimmed
        let parent = task.parent
        let tentative = SubtaskOutlineEdit.appendSortOrder(parentID: parent?.id, in: outlineRows)
        guard let row = editing.createRow(parent, tentative) else { return }
        // Land directly below the row just finished, not at the end of the level.
        let placement = SubtaskOutlineEdit.placeAfter(anchorID: task.id, parentID: parent?.id,
                                                      moving: row.id, in: outlineRows)
        row.sortOrder = placement.order
        let all = allTasksInSubtree
        for (id, order) in placement.shifted { all.first { $0.id == id }?.sortOrder = order }
        editing.selection.wrappedValue = [row.id]
        selectionAnchor = row.id
        focusedId.wrappedValue = row.id
    }

    /// Backspace in an empty field: drop the row and put the caret at the end of the one above.
    private func removeEmptyFocusedRow() -> Bool {
        guard let editing, let focused = focusedId.wrappedValue,
              let task = allTasksInSubtree.first(where: { $0.id == focused })
        else { return false }
        let flat = flatVisibleTasks
        let previous = flat.firstIndex(where: { $0.id == focused }).flatMap { $0 > 0 ? flat[$0 - 1] : nil }
        focusedId.wrappedValue = previous?.id
        editing.selection.wrappedValue = previous.map { [$0.id] } ?? []
        dropRow(task)
        return true
    }

    /// Deleting a row whose view is still mounted must wait for the update pass to finish. Reading a
    /// deleted SwiftData model's stored properties **traps** (the SIGTRAP class `ModelLiveness` exists for),
    /// and a delete issued from a key handler or a commit lands while the row — and the page around it — is
    /// mid-render. Focus and selection are moved off the row first, then this runs a turn later.
    private func dropRow(_ task: Task) {
        DispatchQueue.main.async { onDelete(task) }
    }

    /// Delete over a selection. Confirms only when the cascade would take rows you can't see.
    private func deleteSelection() -> Bool {
        guard editing != nil, !selectedIDs.isEmpty else { return false }
        let scope = SubtaskOutlineEdit.deletionScope(selected: selectedIDs, in: outlineRows)
        guard !scope.ids.isEmpty else { return false }
        if scope.needsConfirmation { pendingDelete = scope } else { applyDelete(scope) }
        return true
    }

    private func applyDelete(_ scope: SubtaskOutlineEdit.DeletionScope) {
        let all = allTasksInSubtree
        // Only the roots are handed over — `Task.children` cascades the descendants.
        for id in scope.roots {
            if let task = all.first(where: { $0.id == id }) { dropRow(task) }
        }
        editing?.selection.wrappedValue = []
        selectionAnchor = nil
        pendingDelete = nil
    }


    /// Return with a selection but nothing being typed: start editing the (first) selected row.
    private func editSelection() -> Bool {
        guard editing != nil else { return false }
        let flat = flatVisibleTasks
        guard let first = flat.first(where: { selectedIDs.contains($0.id) }) else { return false }
        focusedId.wrappedValue = first.id
        return true
    }

    /// Escape, in three stages: commit the edit → clear the selection → fall through (so a sheet closes).
    private func escape() -> Bool {
        guard let editing else { return false }
        if let focused = focusedId.wrappedValue {
            focusedId.wrappedValue = nil          // losing focus flushes the field into the model
            editing.selection.wrappedValue = [focused]
            return true
        }
        if !editing.selection.wrappedValue.isEmpty {
            editing.selection.wrappedValue = []
            selectionAnchor = nil
            return true
        }
        return false
    }

    /// Tab/Shift-Tab over a selection (not while typing — that path is `EntryInlineKeyHandling`).
    private func depthChangeOnSelection(outdent: Bool) -> Bool {
        guard editing != nil, selectedIDs.count == 1,
              let task = allTasksInSubtree.first(where: { selectedIDs.contains($0.id) })
        else { return false }
        if outdent { outdentRow(task) } else { indentRow(task) }
        return true
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
            if editing != nil { addRowButton }
        }
        .sheet(item: $editingTask) { task in
            TaskEditorSheet(task: task, defaultDate: defaultDate)
        }
        .alert("Delete \(pendingDelete?.directCount ?? 0) task\(pendingDelete?.directCount == 1 ? "" : "s")?",
               isPresented: Binding(get: { pendingDelete != nil },
                                    set: { if !$0 { pendingDelete = nil } })) {
            Button("Delete", role: .destructive) { if let s = pendingDelete { applyDelete(s) } }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            // Name the part that isn't on screen: `Task.children` cascades and there is no undo.
            Text("This also deletes \(pendingDelete?.descendantCount ?? 0) subtask"
                 + "\(pendingDelete?.descendantCount == 1 ? "" : "s") beneath "
                 + "\((pendingDelete?.directCount ?? 0) == 1 ? "it" : "them").")
        }
        #if os(macOS)
        // Only the surfaces that opted into editing install the monitor, so the diary and meetings are
        // untouched by it. Every key is guarded on whether a field is being typed into — see the monitor.
        .onAppear {
            guard editing != nil else { return }
            keys.onReturn = { editSelection() }
            keys.onDelete = { deleteSelection() }
            keys.onTab = { depthChangeOnSelection(outdent: false) }
            keys.onBackTab = { depthChangeOnSelection(outdent: true) }
            keys.onBackspaceInEmptyField = { removeEmptyFocusedRow() }
            keys.onEscape = { escape() }
            keys.start()
        }
        .onDisappear { keys.stop() }
        #endif
    }

    /// Adds a row at the container's top level — depth 0 every time, so the button means one thing.
    private var addRowButton: some View {
        Button(action: addRow) {
            Label("Add subtask", systemImage: "plus.circle.fill")
                .font(AppTheme.bodyFont(size: 12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .keyboardShortcut("n", modifiers: [.command, .shift])
    }

    @ViewBuilder
    private func taskNotesArea(for task: Task) -> some View {
        let hasNotes = !(task.notes ?? "").isEmpty
        let isNotesFocused = focusedId.wrappedValue == task.notesAreaFocusId
        if (hasNotes || isNotesFocused) && !collapsedIds.wrappedValue.contains(task.id) {
            // Mirror taskRow's HStack structure: spacer matches chevron width, same spacing.
            HStack(alignment: .top, spacing: 4) {
                Color.clear.frame(width: 14)
                EntryNotesSubArea(
                    text: Binding(
                        get: { task.notes ?? "" },
                        set: { task.notes = $0.isEmpty ? nil : $0 }
                    ),
                    isFocused: isNotesFocused,
                    focusedEntryId: focusedId,
                    focusId: task.notesAreaFocusId,
                    placeholder: "Add notes…",
                    onMoveToPrevious: { focusedId.wrappedValue = task.id },
                    onMoveToNext: notesNextMove(for: task)
                )
            }
            .padding(.horizontal, 8)
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
        let view = HStack(alignment: .top, spacing: 4) {
            Color.clear.frame(width: 14)
            VStack(alignment: .leading, spacing: 0) {
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
        }
        .padding(.leading, 8)
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

            InlineEditableSingleLineText(
                placeholder: "",
                text: Binding(get: { task.summary }, set: { task.summary = $0 }),
                isFocused: focusedId.wrappedValue == task.id,
                focusBinding: focusedId,
                focusId: task.id,
                struckThrough: task.status == .completed || task.status == .cancelled,
                foregroundColor: task.status == .cancelled ? .secondary : .primary,
                onIndent: editing == nil ? nil : { indentRow(task) },
                onOutdent: editing == nil ? nil : { outdentRow(task) },
                onMoveToPrevious: prevMove(for: task),
                onMoveToNext: nextMove(for: task),
                onTap: editing == nil ? nil : { select(task) },
                onCommit: editing == nil ? nil : { draft in commitRow(task, draft: draft) }
            )

            // No pencil: double-click opens the task's page (the row-tap rule for a rich entity), and the
            // context menu keeps the editor sheet.
            if editing == nil { InlineRowEditButton(action: { editingTask = task }) }
            if focusedId.wrappedValue != task.id {
                Spacer(minLength: 0)
            }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background {
            if selectedIDs.contains(task.id) {
                RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.18))
            }
        }
        .onTapGesture(count: 2) { editing?.openTask(task) }
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
        .contextMenu {
            if let editing {
                Button("Open Task Page") { editing.openTask(task) }
            }
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
