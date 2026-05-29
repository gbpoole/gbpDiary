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

// MARK: - Shared day content (used by DayView and WeekView)

struct DayPageContent: View {
    let date: Date
    var dayRecord: DayRecord?
    let allTasks: [Task]
    var showBacklog: Bool = true
    var showTaskSections: Bool = true

    @Environment(\.modelContext) private var modelContext
    @FocusState private var focusedEntryId: UUID?
    @State private var pendingFocusId: UUID?
    @State private var showingAddTask = false
    @State private var editingTask: Task?
    #if os(macOS)
    @State private var deleteMonitor = DeleteKeyMonitor()
    @State private var focusClearMonitor = FocusClearMonitor()
    #endif

    @State private var selectedEntry: DayEntry?
    @State private var activeDropZone: Int?

    @Query(sort: \Minutes.meetingAt, order: .reverse) private var allMinutes: [Minutes]

    private var dayStart: Date { DayTaskFiltering.dayBounds(for: date).dayStart }
    private var dayEnd: Date { DayTaskFiltering.dayBounds(for: date).dayEnd }

    private var entries: [DayEntry] {
        (dayRecord?.entries ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    private var taskEntryIds: Set<PersistentIdentifier> {
        Set(entries.compactMap { $0.task?.persistentModelID })
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

            if let entry = selectedEntry {
                Divider()
                EntryDetailPanel(entry: entry, onDismiss: { selectedEntry = nil })
                    .frame(width: 280)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedEntry?.id)
        .sheet(isPresented: $showingAddTask) {
            TaskEditorSheet(task: nil, defaultDate: date) { newTask in
                let record = findOrCreateDayRecord()
                let entry = DayEntry(kind: .task, sortOrder: nextSortOrder(record))
                entry.task = newTask
                entry.dayRecord = record
                modelContext.insert(entry)
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
        #if os(macOS)
        .onAppear {
            deleteMonitor.start()
            focusClearMonitor.action = { if focusedEntryId != nil { focusedEntryId = nil } }
            focusClearMonitor.start()
        }
        .onDisappear {
            deleteMonitor.stop()
            focusClearMonitor.stop()
        }
        .onChange(of: focusedEntryId) { _, newId in
            updateDeleteAction(for: newId)
        }
        #endif
    }

    // MARK: - Entry rows

    @ViewBuilder
    private var entryRows: some View {
        DayEntryListView(
            entries: entries,
            activeDropZone: $activeDropZone,
            onMoveEntry: moveEntry
        ) { entry, index in
            entryRow(entry: entry, index: index)
        }
    }

    @ViewBuilder
    private func entryRow(entry: DayEntry, index: Int) -> some View {
        let onSelect: (() -> Void)? = entry.detailTarget != nil ? {
            withAnimation(.easeInOut(duration: 0.2)) {
                if selectedEntry?.id == entry.id {
                    selectedEntry = nil
                } else {
                    selectedEntry = entry
                }
            }
        } : nil
        EntryRowView(
            entry: entry,
            focusedEntryId: $focusedEntryId,
            onAddNoteAfter: entry.kind == .note ? { insertNoteAfter(entry) } : nil,
            onMoveToPrevious: index > 0 ? { pendingFocusId = entries[index - 1].id } : nil,
            onMoveToNext: index < entries.count - 1 ? { pendingFocusId = entries[index + 1].id } : nil,
            onDeleteEmpty: {
                let prevId = index > 0 ? entries[index - 1].id : nil
                deleteEntry(entry, focusingId: prevId)
            },
            onIndent: { indentEntry(entry) },
            onOutdent: { outdentEntry(entry) },
            onSelect: onSelect
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
        if entries.isEmpty && (!showTaskSections || (scheduled.isEmpty && followUpsDue.isEmpty &&
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
        (record.entries.map(\.sortOrder).max() ?? -1) + 1
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
        if selectedEntry?.id == entry.id { selectedEntry = nil }
        if let id = focusingId { pendingFocusId = id }
        modelContext.delete(entry)
    }

    private func indentEntry(_ entry: DayEntry) {
        DayEntryOrdering.indent(entry: entry, in: entries)
    }

    private func outdentEntry(_ entry: DayEntry) {
        DayEntryOrdering.outdent(entry: entry, in: entries)
    }

    #if os(macOS)
    private func updateDeleteAction(for focusId: UUID?) {
        guard let focusId,
              let idx = entries.firstIndex(where: { $0.id == focusId }) else {
            deleteMonitor.action = nil
            return
        }
        let entry = entries[idx]
        let prevId = idx > 0 ? entries[idx - 1].id : nil
        deleteMonitor.action = {
            guard entry.isInlineSummaryEmpty else { return false }
            deleteEntry(entry, focusingId: prevId)
            return true
        }
    }
    #endif

    private func moveEntry(_ dragged: DayEntry, toDropIndex dropIndex: Int) {
        DayEntryOrdering.moveEntry(dragged, toDropIndex: dropIndex, in: entries)
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

    var body: some View {
        ScrollView {
            DayPageContent(date: date, dayRecord: dayRecord, allTasks: allTasks,
                           showTaskSections: false)
                .padding(.vertical)
        }
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
