import SwiftUI
import SwiftData

// MARK: - NSEvent-level delete key monitor

// onKeyPress(.delete) cannot intercept ⌫ in a TextField because NSTextField's
// deleteBackward: action fires inside interpretKeyEvents:, which SwiftUI runs
// after onKeyPress is consulted but before the closure can suppress it.
// A local NSEvent monitor fires before any responder touches the event.
#if os(macOS)
private final class DeleteKeyMonitor: @unchecked Sendable {
    private var monitor: Any?
    var action: (() -> Bool)?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 51 else { return event }  // 51 = ⌫
            let handled = MainActor.assumeIsolated { self?.action?() ?? false }
            return handled ? nil : event
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

// Intercepts the Escape key to deactivate the currently focused diary entry.
// Returns the event unconsumed when nothing is focused so sheets and alerts
// can still dismiss themselves with Escape.
private final class EscapeKeyMonitor: @unchecked Sendable {
    private var monitor: Any?
    var action: (() -> Bool)?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }  // 53 = ⎋
            let handled = MainActor.assumeIsolated { self?.action?() ?? false }
            return handled ? nil : event
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

// Monitors leftMouseDown events and calls action whenever the click lands
// outside an NSTextView. Used to clear the focused note entry on outside clicks
// and to defocus before a drag begins, ensuring the drag-blocking overlay
// reappears on the previously-focused note before any drag arrives.
private final class FocusClearMonitor: @unchecked Sendable {
    private var monitor: Any?
    var action: (() -> Void)?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let action = self?.action,
                  let hit = NSApp.keyWindow?.contentView?.hitTest(event.locationInWindow),
                  !(hit is NSTextView) else { return event }
            MainActor.assumeIsolated(action)
            return event
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}
#endif

// MARK: - Shared banner message type

struct BannerMessage: Equatable {
    let text: String
    let systemImage: String
    let tint: Color
}

// MARK: - Shared day content (used by DayView and WeekView)

struct DayPageContent: View {
    let date: Date
    var dayRecord: DayRecord?
    let allTasks: [Task]
    var showBacklog: Bool = true
    var showTaskSections: Bool = true
    var onShowBanner: (BannerMessage) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @FocusState private var focusedEntryId: UUID?
    @State private var pendingFocusId: UUID?
    @State private var showingAddTask = false
    @State private var editingTask: Task?
    #if os(macOS)
    @State private var deleteMonitor = DeleteKeyMonitor()
    @State private var focusClearMonitor = FocusClearMonitor()
    @State private var escapeMonitor = EscapeKeyMonitor()
    #endif

    @State private var selectedItem: DiaryItem?
    @State private var activeDropZone: Int?
    @State private var collapsedEntryIds: Set<UUID> = []

    @Query(sort: \Minutes.meetingAt, order: .reverse) private var allMinutes: [Minutes]

    private var dayStart: Date { DayTaskFiltering.dayBounds(for: date).dayStart }
    private var dayEnd: Date { DayTaskFiltering.dayBounds(for: date).dayEnd }

    // Non-task DayEntries (notes and meetings), sorted for display.
    private var entries: [DayEntry] {
        (dayRecord?.entries ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    // All diary items: root tasks (dayRecord-owned) merged with non-task DayEntries.
    private var diaryItems: [DiaryItem] {
        let taskItems = (dayRecord?.tasks ?? [])
            .filter { $0.parent == nil }
            .map(DiaryItem.task)
        let entryItems = (dayRecord?.entries ?? []).map(DiaryItem.entry)
        return (taskItems + entryItems).sorted { $0.sortOrder < $1.sortOrder }
    }

    // Items visible after applying collapse logic (only hides DayEntry-level children).
    private var visibleDiaryItems: [DiaryItem] {
        var result: [DiaryItem] = []
        var hidingBelowLevel: Int? = nil
        for item in diaryItems {
            switch item {
            case .task:
                hidingBelowLevel = nil  // tasks are root-level; end any hide sequence
                result.append(item)
            case .entry(let entry):
                if let level = hidingBelowLevel {
                    if entry.indentLevel <= level { hidingBelowLevel = nil }
                    else { continue }
                }
                result.append(item)
                if collapsedEntryIds.contains(entry.id) {
                    hidingBelowLevel = entry.indentLevel
                }
            }
        }
        return result
    }

    private func diaryItemNeedsChevron(_ item: DiaryItem) -> Bool {
        switch item {
        case .task(let task):
            return task.needsChevron
        case .entry(let entry):
            switch entry.kind {
            case .meeting:
                let hasMinutes = !(entry.minutes?.minutesContent ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let hasNewTasks = !(entry.minutes?.newTasks ?? []).isEmpty
                let idx = diaryItems.firstIndex(where: { $0.id == entry.id }) ?? diaryItems.count
                let hasChildren = idx + 1 < diaryItems.count
                    && (diaryItems[idx + 1].entryIndentLevel.map { $0 > entry.indentLevel } ?? false)
                return hasMinutes || hasNewTasks || hasChildren
            default:
                let idx = diaryItems.firstIndex(where: { $0.id == entry.id }) ?? diaryItems.count
                return idx + 1 < diaryItems.count
                    && (diaryItems[idx + 1].entryIndentLevel.map { $0 > entry.indentLevel } ?? false)
            }
        }
    }

    private func toggleCollapse(_ entry: DayEntry) {
        if collapsedEntryIds.contains(entry.id) {
            collapsedEntryIds.remove(entry.id)
        } else {
            collapsedEntryIds.insert(entry.id)
        }
    }

    @discardableResult
    private func absorbAndMergeNotes() -> [UUID: DayEntry] {
        let (absorbMap, absorbDelete) = DayEntryOrdering.absorbAdjacentNotes(in: entries)
        for entry in absorbDelete { modelContext.delete(entry) }
        if !absorbDelete.isEmpty {
            onShowBanner(BannerMessage(text: "Note absorbed into entry.", systemImage: "arrow.down.to.line", tint: .accentColor))
        }
        let (mergeMap, mergeDelete) = DayEntryOrdering.mergeAdjacentNotes(in: entries)
        for entry in mergeDelete { modelContext.delete(entry) }
        if !mergeDelete.isEmpty {
            onShowBanner(BannerMessage(text: "Notes merged.", systemImage: "arrow.triangle.merge", tint: .accentColor))
        }
        return mergeMap.merging(absorbMap) { _, new in new }
    }

    private func splitNote(_ entry: DayEntry) {
        #if os(macOS)
        guard entry.kind == .note,
              let tv = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
        let currentText = tv.string
        let splitPoint = min(tv.selectedRange().location, currentText.utf16.count)
        let ns = currentText as NSString
        let before = ns.substring(to: splitPoint).trimmingCharacters(in: .whitespacesAndNewlines)
        let after  = ns.substring(from: splitPoint).trimmingCharacters(in: .whitespacesAndNewlines)
        entry.text = before
        let record = findOrCreateDayRecord()
        for e in record.entries where e.sortOrder > entry.sortOrder { e.sortOrder += 1 }
        let newEntry = DayEntry(kind: .note, text: after,
                                sortOrder: entry.sortOrder + 1,
                                indentLevel: entry.indentLevel)
        newEntry.dayRecord = record
        modelContext.insert(newEntry)
        pendingFocusId = newEntry.id
        onShowBanner(BannerMessage(text: "Note split.", systemImage: "scissors", tint: .accentColor))
        #endif
    }

    private var taskEntryIds: Set<PersistentIdentifier> {
        DayTaskFiltering.taskEntryIds(from: dayRecord)
    }

    private var scheduled: [Task] {
        DayTaskFiltering.scheduledTasks(allTasks: allTasks, dayStart: dayStart, dayEnd: dayEnd, taskEntryIds: taskEntryIds)
    }

    private var followUpsDue: [Task] {
        DayTaskFiltering.followUpsDueTasks(allTasks: allTasks, dayEnd: dayEnd)
    }

    private var backlog: [Task] {
        DayTaskFiltering.backlogTasks(allTasks: allTasks, dayStart: dayStart)
    }

    private var completedToday: [Task] {
        DayTaskFiltering.completedTodayTasks(allTasks: allTasks, dayStart: dayStart, dayEnd: dayEnd)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    entryRows
                    addEntryBar
                    taskSections
                    emptyState
                }
            }

            if let item = selectedItem {
                Divider()
                EntryDetailPanel(item: item, onDismiss: { selectedItem = nil })
                    .frame(width: 280)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedItem?.id)
        .sheet(isPresented: $showingAddTask) {
            TaskEditorSheet(task: nil, defaultDate: date) { newTask in
                let record = findOrCreateDayRecord()
                newTask.dayRecord = record
                newTask.sortOrder = nextSortOrder(record)
            }
        }
        .sheet(item: $editingTask) { task in
            TaskEditorSheet(task: task, defaultDate: date)
        }
        .onChange(of: pendingFocusId) { _, newId in
            if let id = newId {
                focusedEntryId = id
                pendingFocusId = nil
            }
        }
        .onChange(of: collapsedEntryIds) { _, _ in
            if let sel = selectedItem,
               !visibleDiaryItems.contains(where: { $0.id == sel.id }) {
                withAnimation(.easeInOut(duration: 0.2)) { selectedItem = nil }
            }
        }
        #if os(macOS)
        .onAppear {
            deleteMonitor.start()
            focusClearMonitor.action = { if focusedEntryId != nil { focusedEntryId = nil } }
            focusClearMonitor.start()
            escapeMonitor.action = {
                guard focusedEntryId != nil else { return false }
                focusedEntryId = nil
                return true
            }
            escapeMonitor.start()
        }
        .onDisappear {
            deleteMonitor.stop()
            focusClearMonitor.stop()
            escapeMonitor.stop()
        }
        .onChange(of: focusedEntryId) { _, newId in
            updateDeleteAction(for: newId)
            absorbAndMergeNotes()
        }
        #endif
    }

    // MARK: - Entry rows

    // Returns a Task that lives inside a meeting's newTasks list, looked up by Task UUID.
    // Searches all descendants, not just top-level tasks.
    // Returns nil for DayEntry UUIDs or any UUID not found in meeting task lists.
    private func findMeetingTask(id: UUID) -> Task? {
        func search(_ tasks: [Task]) -> Task? {
            for task in tasks {
                if task.id == id { return task }
                if let found = search(task.children) { return found }
            }
            return nil
        }
        for entry in entries where entry.kind == .meeting {
            if let found = search(entry.minutes?.newTasks ?? []) { return found }
        }
        return nil
    }

    // Returns a Task that is a descendant (non-root) of any diary task in the list.
    // Used so diary subtasks can be dragged to diary-level drop zones to become root tasks.
    private func findDiarySubtask(id: UUID) -> Task? {
        func search(_ tasks: [Task]) -> Task? {
            for t in tasks {
                if t.id == id { return t }
                if let found = search(t.children) { return found }
            }
            return nil
        }
        for item in diaryItems {
            if case .task(let root) = item {
                if let found = search(root.children) { return found }
            }
        }
        return nil
    }

    // Searches all tasks visible on this day — diary roots, their subtrees, and all
    // meeting task trees. Used by subtask-drop handlers that accept any task UUID.
    private func findAnyTask(id: UUID) -> Task? {
        func search(_ list: [Task]) -> Task? {
            for t in list {
                if t.id == id { return t }
                if let found = search(t.children) { return found }
            }
            return nil
        }
        for item in diaryItems {
            if case .task(let root) = item {
                if let found = search([root]) { return found }
            }
        }
        for entry in entries where entry.kind == .meeting {
            if let found = search(entry.minutes?.newTasks ?? []) { return found }
        }
        return nil
    }

    // Recursively clears originMinutes for a task and all its descendants.
    private func clearOriginMinutes(_ task: Task) {
        task.originMinutes = nil
        for child in task.children { clearOriginMinutes(child) }
    }

    // Moves any diary task (root or subtask) into a meeting.
    private func moveDiaryTaskToMeeting(_ task: Task, minutes: Minutes) {
        task.parent = nil          // detach from any parent (no-op for root diary tasks)
        task.dayRecord = nil
        task.originMinutes = minutes
        task.sortOrder = (minutes.newTasks.map(\.sortOrder).max() ?? -1) + 1
        renormalizeSortOrders()
    }

    // Moves a meeting task into the diary at the given visible drop index.
    private func placeMeetingTaskInDiary(_ task: Task, atVisibleDropIndex dropIndex: Int) {
        let record = findOrCreateDayRecord()
        let existing = diaryItems  // snapshot before the task joins the diary
        clearOriginMinutes(task)

        let fullTarget: Int
        if dropIndex == 0 {
            fullTarget = 0
        } else {
            let preceding = visibleDiaryItems[min(dropIndex - 1, visibleDiaryItems.count - 1)]
            fullTarget = (existing.firstIndex(where: { $0.id == preceding.id }) ?? existing.count - 1) + 1
        }

        var reordered = existing
        reordered.insert(.task(task), at: min(fullTarget, reordered.count))
        for (i, item) in reordered.enumerated() {
            switch item {
            case .task(let t): t.sortOrder = i
            case .entry(let e): e.sortOrder = i
            }
        }
        task.dayRecord = record
        absorbAndMergeNotes()
    }

    @ViewBuilder
    private var entryRows: some View {
        DayEntryListView(
            items: visibleDiaryItems,
            activeDropZone: $activeDropZone,
            onMoveItem: moveDiaryItemFromVisible,
            onDropForeignUUID: { uuidString, dropIndex in
                guard let id = UUID(uuidString: uuidString) else { return false }
                if let task = findMeetingTask(id: id) {
                    placeMeetingTaskInDiary(task, atVisibleDropIndex: dropIndex)
                    onShowBanner(BannerMessage(text: "Task removed from meeting.", systemImage: "arrow.turn.up.left", tint: .accentColor))
                    return true
                }
                if let task = findDiarySubtask(id: id) {
                    let record = findOrCreateDayRecord()
                    task.parent = nil
                    task.dayRecord = record
                    task.sortOrder = nextSortOrder(record)
                    renormalizeSortOrders()
                    onShowBanner(BannerMessage(text: "Task promoted to diary.", systemImage: "arrow.turn.up.left", tint: .accentColor))
                    return true
                }
                return false
            },
            draggableId: { item in
                switch item {
                case .entry(let e) where e.kind == .meeting: return nil  // header card applies its own drag
                case .task: return nil  // DiaryTaskRow.rowCard applies its own drag
                default: return item.id.uuidString
                }
            }
        ) { item, index in
            diaryItemRow(item: item, index: index)
        }
    }

    @ViewBuilder
    private func diaryItemRow(item: DiaryItem, index: Int) -> some View {
        switch item {
        case .task(let task): taskDiaryRow(task: task, index: index)
        case .entry(let entry): entryRow(entry: entry, index: index)
        }
    }

    @ViewBuilder
    private func taskDiaryRow(task: Task, index: Int) -> some View {
        let prevId: UUID? = index > 0 ? visibleDiaryItems[index - 1].id : nil
        let nextId: UUID? = index < visibleDiaryItems.count - 1 ? visibleDiaryItems[index + 1].id : nil
        DiaryTaskRow(
            task: task,
            focusedEntryId: $focusedEntryId,
            isCollapsed: collapsedEntryIds.contains(task.id),
            onToggleCollapse: {
                if collapsedEntryIds.contains(task.id) { collapsedEntryIds.remove(task.id) }
                else { collapsedEntryIds.insert(task.id) }
            },
            onMoveToPrevious: prevId.map { id in { pendingFocusId = id } },
            onMoveToNext: nextId.map { id in { pendingFocusId = id } },
            onMoveToNextFromNotes: nextId.map { id in { pendingFocusId = id } },
            onIndent: { indentDiaryTask(task) },
            onSelect: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if case .task(let sel) = selectedItem, sel.id == task.id {
                        selectedItem = nil
                    } else {
                        selectedItem = .task(task)
                    }
                }
            },
            onDropOntoTask: { uuidString in
                guard let id = UUID(uuidString: uuidString), id != task.id else { return false }
                // Note entry → absorb into task notes
                if let diaryItem = diaryItems.first(where: { $0.id == id }),
                   case .entry(let noteEntry) = diaryItem,
                   noteEntry.kind == .note {
                    let text = noteEntry.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return false }
                    let existing = (task.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    task.notes = existing.isEmpty ? text : existing + "\n\n" + text
                    modelContext.delete(noteEntry)
                    onShowBanner(BannerMessage(text: "Note added to task.", systemImage: "arrow.down.to.line", tint: .accentColor))
                    return true
                }
                // Diary task → make subtask
                if let diaryItem = diaryItems.first(where: { $0.id == id }),
                   case .task(let dragged) = diaryItem {
                    dragged.parent = task
                    dragged.dayRecord = nil
                    dragged.originMinutes = nil
                    renormalizeSortOrders()
                    onShowBanner(BannerMessage(text: "Task added as subtask.", systemImage: "arrow.turn.down.right", tint: .accentColor))
                    return true
                }
                // Meeting task → make subtask
                if let dragged = findMeetingTask(id: id) {
                    dragged.parent = task
                    dragged.originMinutes = nil
                    dragged.dayRecord = nil
                    onShowBanner(BannerMessage(text: "Task added as subtask.", systemImage: "arrow.turn.down.right", tint: .accentColor))
                    return true
                }
                // Diary subtask → make subtask of this task
                if let dragged = findDiarySubtask(id: id), dragged.id != task.id {
                    dragged.parent = task
                    dragged.dayRecord = nil
                    dragged.originMinutes = nil
                    renormalizeSortOrders()
                    onShowBanner(BannerMessage(text: "Task added as subtask.", systemImage: "arrow.turn.down.right", tint: .accentColor))
                    return true
                }
                return false
            },
            onExternalDropOntoSubtask: { uuidString, targetTask in
                guard let id = UUID(uuidString: uuidString),
                      let dragged = findAnyTask(id: id),
                      dragged.id != targetTask.id else { return false }
                dragged.parent = targetTask
                dragged.dayRecord = nil
                dragged.originMinutes = nil
                renormalizeSortOrders()
                onShowBanner(BannerMessage(text: "Task added as subtask.", systemImage: "arrow.turn.down.right", tint: .accentColor))
                return true
            },
            onExternalDropIntoSubtree: { uuidString in
                guard let id = UUID(uuidString: uuidString),
                      let dragged = findAnyTask(id: id),
                      dragged.id != task.id else { return false }
                dragged.parent = task
                dragged.dayRecord = nil
                dragged.originMinutes = nil
                renormalizeSortOrders()
                onShowBanner(BannerMessage(text: "Task added as subtask.", systemImage: "arrow.turn.down.right", tint: .accentColor))
                return true
            }
        )
    }

    @ViewBuilder
    private func entryRow(entry: DayEntry, index: Int) -> some View {
        let onSelect: (() -> Void)? = entry.detailTarget != nil ? {
            withAnimation(.easeInOut(duration: 0.2)) {
                if case .entry(let sel) = selectedItem, sel.id == entry.id {
                    selectedItem = nil
                } else {
                    selectedItem = .entry(entry)
                }
            }
        } : nil
        let isNotesFocused = focusedEntryId == entry.notesAreaFocusId
        let onDropOntoEntry: ((String) -> Bool)? = entry.kind == .meeting ? { uuidString in
            guard let id = UUID(uuidString: uuidString),
                  let minutes = entry.minutes else { return false }
            // Note → absorb into meeting minutes
            if let diaryItem = diaryItems.first(where: { $0.id == id }),
               case .entry(let noteEntry) = diaryItem,
               noteEntry.kind == .note {
                let text = noteEntry.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return false }
                let existing = (minutes.minutesContent ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                minutes.minutesContent = existing.isEmpty ? text : existing + "\n\n" + text
                modelContext.delete(noteEntry)
                onShowBanner(BannerMessage(text: "Note added to meeting.", systemImage: "arrow.down.to.line", tint: .accentColor))
                return true
            }
            // Diary task → move to meeting
            if let diaryItem = diaryItems.first(where: { $0.id == id }),
               case .task(let task) = diaryItem {
                moveDiaryTaskToMeeting(task, minutes: minutes)
                onShowBanner(BannerMessage(text: "Task added to meeting.", systemImage: "arrow.down.to.line", tint: .accentColor))
                return true
            }
            // Meeting task from another meeting
            if let task = findMeetingTask(id: id) {
                task.originMinutes = minutes
                task.sortOrder = (minutes.newTasks.map(\.sortOrder).max() ?? -1) + 1
                onShowBanner(BannerMessage(text: "Task moved to meeting.", systemImage: "arrow.down.to.line", tint: .accentColor))
                return true
            }
            // Diary subtask → move to meeting
            if let task = findDiarySubtask(id: id) {
                moveDiaryTaskToMeeting(task, minutes: minutes)
                onShowBanner(BannerMessage(text: "Task added to meeting.", systemImage: "arrow.down.to.line", tint: .accentColor))
                return true
            }
            return false
        } : nil
        EntryRowView(
            entry: entry,
            focusedEntryId: $focusedEntryId,
            onAddNoteAfter: entry.kind == .note ? { insertNoteAfter(entry) } : nil,
            onMoveToPrevious: index > 0 ? { pendingFocusId = visibleDiaryItems[index - 1].id } : nil,
            onMoveToNext: index < visibleDiaryItems.count - 1
                ? { pendingFocusId = visibleDiaryItems[index + 1].id }
                : nil,
            onDeleteEmpty: {
                let prevId = index > 0 ? visibleDiaryItems[index - 1].id : nil
                deleteEntry(entry, focusingId: prevId)
            },
            onIndent: { indentEntry(entry) },
            onOutdent: { outdentEntry(entry) },
            onSelect: onSelect,
            hasChildren: diaryItemNeedsChevron(.entry(entry)),
            isCollapsed: collapsedEntryIds.contains(entry.id),
            onToggleCollapse: { toggleCollapse(entry) },
            onSplitNote: entry.kind == .note ? { splitNote(entry) } : nil,
            isNotesFocused: isNotesFocused,
            onMoveToNextFromNotes: index < visibleDiaryItems.count - 1
                ? { pendingFocusId = visibleDiaryItems[index + 1].id }
                : nil,
            onDropDiaryEntry: entry.kind == .meeting ? { uuidString in
                guard let id = UUID(uuidString: uuidString),
                      let minutes = entry.minutes
                else { return false }
                if let diaryItem = diaryItems.first(where: { $0.id == id }),
                   case .task(let task) = diaryItem {
                    moveDiaryTaskToMeeting(task, minutes: minutes)
                    onShowBanner(BannerMessage(text: "Task added to meeting.", systemImage: "arrow.down.to.line", tint: .accentColor))
                    return true
                }
                if let task = findMeetingTask(id: id) {
                    task.originMinutes = minutes
                    task.sortOrder = (minutes.newTasks.map(\.sortOrder).max() ?? -1) + 1
                    onShowBanner(BannerMessage(text: "Task moved to meeting.", systemImage: "arrow.down.to.line", tint: .accentColor))
                    return true
                }
                // Diary subtask → move to meeting
                if let task = findDiarySubtask(id: id) {
                    moveDiaryTaskToMeeting(task, minutes: minutes)
                    onShowBanner(BannerMessage(text: "Task added to meeting.", systemImage: "arrow.down.to.line", tint: .accentColor))
                    return true
                }
                return false
            } : nil,
            onDropOntoEntry: onDropOntoEntry,
            onRemoveFromMeeting: entry.kind == .meeting ? { task in
                let record = findOrCreateDayRecord()
                clearOriginMinutes(task)
                task.dayRecord = record
                task.sortOrder = nextSortOrder(record)
                renormalizeSortOrders()
                absorbAndMergeNotes()
                onShowBanner(BannerMessage(text: "Task removed from meeting.", systemImage: "arrow.turn.up.left", tint: .accentColor))
            } : nil,
            onDropExternalOntoMeetingTask: entry.kind == .meeting ? { uuidString, targetTask in
                guard let id = UUID(uuidString: uuidString) else { return false }
                // Diary task dropped onto a meeting task to make it a subtask
                if let diaryItem = diaryItems.first(where: { $0.id == id }),
                   case .task(let task) = diaryItem {
                    task.parent = targetTask
                    task.dayRecord = nil
                    task.originMinutes = entry.minutes
                    renormalizeSortOrders()
                    onShowBanner(BannerMessage(text: "Task added as subtask.", systemImage: "arrow.turn.down.right", tint: .accentColor))
                    return true
                }
                // Diary subtask dropped onto a meeting task to make it a subtask
                if let task = findDiarySubtask(id: id) {
                    task.parent = targetTask
                    task.dayRecord = nil
                    task.originMinutes = entry.minutes
                    renormalizeSortOrders()
                    onShowBanner(BannerMessage(text: "Task added as subtask.", systemImage: "arrow.turn.down.right", tint: .accentColor))
                    return true
                }
                return false
            } : nil
        )
    }

    // MARK: - Task sections

    @ViewBuilder
    private var taskSections: some View {
        if showTaskSections {
            if !scheduled.isEmpty {
                SectionHeader(title: "Scheduled")
                ForEach(scheduled) { task in
                    TaskRowView(task: task, onEdit: { editingTask = task })
                }
            }

            if !followUpsDue.isEmpty {
                SectionHeader(title: "Follow-ups Due")
                ForEach(followUpsDue) { task in
                    TaskRowView(task: task, onEdit: { editingTask = task })
                }
            }

            if showBacklog {
                SectionHeader(title: "Backlog")
                if backlog.isEmpty {
                    Text("Nothing in the backlog.")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                } else {
                    ForEach(backlog) { task in
                        TaskRowView(task: task, onEdit: { editingTask = task })
                    }
                }
            }

            if !completedToday.isEmpty {
                SectionHeader(title: "Completed Today")
                ForEach(completedToday) { task in
                    TaskRowView(task: task, onEdit: { editingTask = task })
                }
            }
        }
    }

    // MARK: - Empty state

    @ViewBuilder
    private var emptyState: some View {
        if diaryItems.isEmpty && (!showTaskSections || (scheduled.isEmpty && followUpsDue.isEmpty &&
           (!showBacklog || backlog.isEmpty) && completedToday.isEmpty)) {
            Text("Nothing here.")
                .foregroundStyle(.tertiary)
                .padding(.horizontal)
                .padding(.vertical, 6)
        }
    }

    // MARK: - Add entry bar

    private var addEntryBar: some View {
        Menu {
            Button("Task")    { showingAddTask = true }
            Button("Meeting") { addMeeting() }
        } label: {
            Label("Add Note", systemImage: "plus")
        } primaryAction: {
            addNote()
        }
        .menuStyle(.automatic)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize()
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Entry creation helpers

    private func findOrCreateDayRecord() -> DayRecord {
        if let existing = dayRecord { return existing }
        let record = DayRecord(date: date)
        modelContext.insert(record)
        return record
    }

    private func nextSortOrder(_ record: DayRecord) -> Int {
        let entryMax = record.entries.map(\.sortOrder).max() ?? -1
        let taskMax = record.tasks.filter { $0.parent == nil }.map(\.sortOrder).max() ?? -1
        return max(entryMax, taskMax) + 1
    }

    private func addNote() {
        let record = findOrCreateDayRecord()
        let entry = DayEntry(kind: .note, text: "", sortOrder: nextSortOrder(record))
        entry.dayRecord = record
        modelContext.insert(entry)
        pendingFocusId = entry.id
    }

    private func insertNoteAfter(_ current: DayEntry) {
        let record = findOrCreateDayRecord()
        for e in record.entries where e.sortOrder > current.sortOrder {
            e.sortOrder += 1
        }
        let entry = DayEntry(kind: .note, text: "", sortOrder: current.sortOrder + 1,
                             indentLevel: current.indentLevel)
        entry.dayRecord = record
        modelContext.insert(entry)
        pendingFocusId = entry.id
    }

    private func deleteEntry(_ entry: DayEntry, focusingId: UUID?) {
        if case .entry(let sel) = selectedItem, sel.id == entry.id { selectedItem = nil }
        if let id = focusingId { pendingFocusId = id }
        modelContext.delete(entry)
        let merged = absorbAndMergeNotes()
        if let pid = pendingFocusId, let absorber = merged[pid] { pendingFocusId = absorber.id }
    }

    private func indentEntry(_ entry: DayEntry) {
        if !DayEntryOrdering.indent(entry: entry, in: entries) {
            onShowBanner(BannerMessage(text: "Meetings cannot be nested inside another meeting.", systemImage: "exclamationmark.triangle.fill", tint: .orange))
        } else {
            absorbAndMergeNotes()
        }
    }

    private func outdentEntry(_ entry: DayEntry) {
        if !DayEntryOrdering.outdent(entry: entry, in: entries) {
            onShowBanner(BannerMessage(text: "Meetings cannot be nested inside another meeting.", systemImage: "exclamationmark.triangle.fill", tint: .orange))
        } else {
            absorbAndMergeNotes()
        }
    }

    #if os(macOS)
    private func updateDeleteAction(for focusId: UUID?) {
        guard let focusId else { deleteMonitor.action = nil; return }
        if let idx = visibleDiaryItems.firstIndex(where: { $0.id == focusId }) {
            let item = visibleDiaryItems[idx]
            let prevId = idx > 0 ? visibleDiaryItems[idx - 1].id : nil
            deleteMonitor.action = {
                switch item {
                case .task(let task):
                    guard task.isInlineSummaryEmpty else { return false }
                    selectedItem = nil
                    if let prevId { pendingFocusId = prevId }
                    modelContext.delete(task)
                    renormalizeSortOrders()
                    return true
                case .entry(let entry):
                    guard entry.isInlineSummaryEmpty else { return false }
                    deleteEntry(entry, focusingId: prevId)
                    return true
                }
            }
        } else {
            deleteMonitor.action = nil
        }
    }
    #endif

    // Renumbers all diary items (tasks + entries) to a clean 0-based sort order
    // preserving their current relative ordering. Called after any structural change
    // to the combined diary list.
    private func renormalizeSortOrders() {
        for (i, item) in diaryItems.enumerated() {
            switch item {
            case .task(let t): t.sortOrder = i
            case .entry(let e): e.sortOrder = i
            }
        }
    }

    // Tab key handler: make the focused root diary task a subtask of the preceding task.
    private func indentDiaryTask(_ task: Task) {
        guard let idx = visibleDiaryItems.firstIndex(where: { $0.id == task.id }),
              idx > 0,
              case .task(let prevTask) = visibleDiaryItems[idx - 1]
        else { return }
        task.parent = prevTask
        task.dayRecord = nil
        task.originMinutes = nil
        renormalizeSortOrders()
    }

    private func moveDiaryItemFromVisible(_ dragged: DiaryItem, toVisibleDropIndex dropIndex: Int) {
        // Convert visible drop index to position in the full combined list
        let fullDropIndex: Int
        if dropIndex == 0 {
            fullDropIndex = 0
        } else {
            let preceding = visibleDiaryItems[dropIndex - 1]
            fullDropIndex = (diaryItems.firstIndex(where: { $0.id == preceding.id }) ?? 0) + 1
        }

        var reordered = diaryItems
        guard let fromIndex = reordered.firstIndex(where: { $0.id == dragged.id }) else { return }
        reordered.remove(at: fromIndex)
        let target = min(fullDropIndex > fromIndex ? fullDropIndex - 1 : fullDropIndex, reordered.count)

        // For DayEntries: infer indentLevel from mixed-list neighbors (tasks count as level 0)
        if case .entry(let draggedEntry) = dragged {
            func indentOf(_ item: DiaryItem) -> Int {
                switch item {
                case .task: return 0
                case .entry(let e): return e.indentLevel
                }
            }
            func kindOf(_ item: DiaryItem) -> DayEntryKind? {
                if case .entry(let e) = item { return e.kind }
                return nil
            }

            let prevLevel = target > 0 ? indentOf(reordered[target - 1]) : 0
            let nextLevel = target < reordered.count ? indentOf(reordered[target]) : 0
            var inferredLevel = nextLevel > prevLevel ? nextLevel : prevLevel

            // Dropping non-meeting directly after a meeting with no deeper item → land inside it
            if target > 0,
               kindOf(reordered[target - 1]) == .meeting,
               draggedEntry.kind != .meeting,
               inferredLevel == indentOf(reordered[target - 1]) {
                inferredLevel = indentOf(reordered[target - 1]) + 1
            }

            // Meeting cannot be nested inside another meeting
            if draggedEntry.kind == .meeting && inferredLevel > 0 {
                for i in (0..<target).reversed() {
                    if indentOf(reordered[i]) < inferredLevel {
                        if kindOf(reordered[i]) == .meeting {
                            onShowBanner(BannerMessage(text: "Meetings cannot be nested inside another meeting.", systemImage: "exclamationmark.triangle.fill", tint: .orange))
                            return
                        }
                        break
                    }
                }
            }
            draggedEntry.indentLevel = inferredLevel
        }

        reordered.insert(dragged, at: target)
        for (i, item) in reordered.enumerated() {
            switch item {
            case .task(let t): t.sortOrder = i
            case .entry(let e): e.sortOrder = i
            }
        }
        absorbAndMergeNotes()
    }

    private func addMeeting() {
        let record = findOrCreateDayRecord()
        let meeting = Minutes(meetingAt: date)
        modelContext.insert(meeting)
        let entry = DayEntry(kind: .meeting, text: "", sortOrder: nextSortOrder(record))
        entry.minutes = meeting
        entry.dayRecord = record
        modelContext.insert(entry)
        pendingFocusId = entry.id
    }
}

// MARK: - Day tab root view

struct DayView: View {
    let date: Date
    let dayRecord: DayRecord?
    let allTasks: [Task]

    @State private var banner: BannerMessage? = nil

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(date, format: .dateTime.weekday(.wide))
                        .font(.title2.bold())
                        .foregroundStyle(isToday ? Color.accentColor : .primary)
                    Text(date, format: .dateTime.day().month(.wide).year())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.top, 28)
                .padding(.bottom, 6)

                Divider()
                    .padding(.horizontal)

                DayPageContent(date: date, dayRecord: dayRecord, allTasks: allTasks,
                               showTaskSections: false,
                               onShowBanner: showBanner)
                    .padding(.vertical)
            }
        }
        .overlay(alignment: .bottom) {
            if let msg = banner { bannerView(msg) }
        }
        .animation(.easeInOut(duration: 0.25), value: banner)
    }

    private func showBanner(_ msg: BannerMessage) {
        banner = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { banner = nil }
    }

    private func bannerView(_ msg: BannerMessage) -> some View {
        HStack(spacing: 8) {
            Image(systemName: msg.systemImage).foregroundStyle(msg.tint)
            Text(msg.text).font(.callout)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 4)
        .padding(.bottom, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Day task sidebar

struct DayTaskSidebar: View {
    let date: Date
    let dayRecord: DayRecord?
    let allTasks: [Task]

    @State private var editingTask: Task?
    @State private var scheduledExpanded = true
    @State private var followUpsExpanded = true
    @State private var backlogExpanded = true
    @State private var completedExpanded = true

    private var dayStart: Date { DayTaskFiltering.dayBounds(for: date).dayStart }
    private var dayEnd: Date { DayTaskFiltering.dayBounds(for: date).dayEnd }

    private var taskEntryIds: Set<PersistentIdentifier> {
        DayTaskFiltering.taskEntryIds(from: dayRecord)
    }

    private var scheduled: [Task] {
        DayTaskFiltering.scheduledTasks(allTasks: allTasks, dayStart: dayStart, dayEnd: dayEnd, taskEntryIds: taskEntryIds)
    }

    private var followUpsDue: [Task] {
        DayTaskFiltering.followUpsDueTasks(allTasks: allTasks, dayEnd: dayEnd)
    }

    private var backlog: [Task] {
        DayTaskFiltering.backlogTasks(allTasks: allTasks, dayStart: dayStart)
    }

    private var completedToday: [Task] {
        DayTaskFiltering.completedTodayTasks(allTasks: allTasks, dayStart: dayStart, dayEnd: dayEnd)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !scheduled.isEmpty {
                    sectionHeader("Scheduled", expanded: $scheduledExpanded)
                    if scheduledExpanded {
                        ForEach(scheduled) { task in
                            TaskRowView(task: task, onEdit: { editingTask = task })
                        }
                    }
                }
                if !followUpsDue.isEmpty {
                    sectionHeader("Follow-ups Due", expanded: $followUpsExpanded)
                    if followUpsExpanded {
                        ForEach(followUpsDue) { task in
                            TaskRowView(task: task, onEdit: { editingTask = task })
                        }
                    }
                }
                sectionHeader("Backlog", expanded: $backlogExpanded)
                if backlogExpanded {
                    if backlog.isEmpty {
                        Text("Nothing in the backlog.")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(backlog) { task in
                            TaskRowView(task: task, onEdit: { editingTask = task })
                        }
                    }
                }
                if !completedToday.isEmpty {
                    sectionHeader("Completed Today", expanded: $completedExpanded)
                    if completedExpanded {
                        ForEach(completedToday) { task in
                            TaskRowView(task: task, onEdit: { editingTask = task })
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .sheet(item: $editingTask) { task in
            TaskEditorSheet(task: task, defaultDate: date)
        }
    }

    private func sectionHeader(_ title: String, expanded: Binding<Bool>) -> some View {
        Button(action: { expanded.wrappedValue.toggle() }) {
            HStack {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared sub-views

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.bold())
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }
}


#Preview {
    DiaryView()
        .modelContainer(for: [Task.self, DayRecord.self, DayEntry.self, Project.self,
                               Person.self, Institution.self, Minutes.self],
                        inMemory: true)
        .frame(width: 600, height: 700)
}
