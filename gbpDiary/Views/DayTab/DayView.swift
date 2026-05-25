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
#endif

// MARK: - Shared day content (used by DayView and WeekView)

struct DayPageContent: View {
    let date: Date
    var dayRecord: DayRecord?
    let allTasks: [Task]
    var showBacklog: Bool = true

    @Environment(\.modelContext) private var modelContext
    @FocusState private var focusedEntryId: UUID?
    @State private var pendingFocusId: UUID?
    @State private var showingAddTask = false
    @State private var showingAddTimesheet = false
    @State private var editingTask: Task?
    #if os(macOS)
    @State private var deleteMonitor = DeleteKeyMonitor()
    #endif

    @Query(sort: \Project.name) private var projects: [Project]
    @Query(sort: \Minutes.meetingAt, order: .reverse) private var allMinutes: [Minutes]

    private var dayStart: Date { Calendar.current.startOfDay(for: date) }
    private var dayEnd: Date   { Calendar.current.date(byAdding: .day, value: 1, to: dayStart)! }

    private var entries: [DayEntry] {
        (dayRecord?.entries ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    private var taskEntryIds: Set<PersistentIdentifier> {
        Set(entries.compactMap { $0.task?.persistentModelID })
    }

    private var scheduled: [Task] {
        allTasks.filter {
            guard let s = $0.scheduledAt else { return false }
            return s >= dayStart && s < dayEnd && $0.status == .open
                && !taskEntryIds.contains($0.persistentModelID)
        }
    }

    private var followUpsDue: [Task] {
        allTasks.filter {
            guard let fu = $0.followUpAt else { return false }
            return fu < dayEnd && $0.status == .followUpPending
        }
    }

    private var backlog: [Task] {
        allTasks.filter {
            $0.status == .open && $0.parent == nil &&
            ($0.scheduledAt == nil || $0.scheduledAt! < dayStart)
        }
    }

    private var completedToday: [Task] {
        allTasks.filter {
            guard let c = $0.completedAt else { return false }
            return c >= dayStart && c < dayEnd
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Free-form entries (notes, tasks added to day, meetings, timesheet)
            if !entries.isEmpty {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    EntryRowView(
                        entry: entry,
                        focusedEntryId: $focusedEntryId,
                        onAddNoteAfter: entry.kind == .note ? { insertNoteAfter(entry) } : nil,
                        onMoveToPrevious: index > 0 ? { pendingFocusId = entries[index - 1].id } : nil,
                        onMoveToNext: index < entries.count - 1 ? { pendingFocusId = entries[index + 1].id } : nil,
                        onDeleteEmpty: {
                            let prevId = index > 0 ? entries[index - 1].id : nil
                            deleteEntry(entry, focusingId: prevId)
                        }
                    )
                }
            }

            addEntryBar

            // Auto-queried task sections (tasks not already in entries)
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

            if entries.isEmpty && scheduled.isEmpty && followUpsDue.isEmpty &&
               (!showBacklog || backlog.isEmpty) && completedToday.isEmpty {
                Text("Nothing here.")
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
            }
        }
        .sheet(isPresented: $showingAddTask) {
            TaskEditorSheet(task: nil, defaultDate: date) { newTask in
                let record = findOrCreateDayRecord()
                let entry = DayEntry(kind: .task, sortOrder: nextSortOrder(record))
                entry.task = newTask
                entry.dayRecord = record
                modelContext.insert(entry)
            }
        }
        .sheet(isPresented: $showingAddTimesheet) {
            AddTimesheetSheet(date: date, projects: projects) { text, duration, project in
                let record = findOrCreateDayRecord()
                let entry = DayEntry(kind: .timesheet, text: text, sortOrder: nextSortOrder(record))
                entry.duration = duration
                entry.project = project
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
        .onAppear { deleteMonitor.start() }
        .onDisappear { deleteMonitor.stop() }
        .onChange(of: focusedEntryId) { _, newId in
            updateDeleteAction(for: newId)
        }
        #endif
    }

    // MARK: - Add entry bar

    private var addEntryBar: some View {
        HStack(spacing: 4) {
            Button(action: addNote) {
                Label("Add Note", systemImage: "plus")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Menu {
                Button("Note")      { addNote() }
                Button("Task")      { showingAddTask = true }
                Button("Meeting")   { addMeeting() }
                Button("Timesheet") { showingAddTimesheet = true }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
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
        if let id = focusingId { pendingFocusId = id }
        modelContext.delete(entry)
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
            guard entry.text.isEmpty else { return false }
            deleteEntry(entry, focusingId: prevId)
            return true
        }
    }
    #endif

    private func addMeeting() {
        let record = findOrCreateDayRecord()
        let entry = DayEntry(kind: .meeting, text: "", sortOrder: nextSortOrder(record))
        entry.dayRecord = record
        modelContext.insert(entry)
    }
}

// MARK: - Day tab root view

struct DayView: View {
    let date: Date

    @Query(sort: \Task.createdAt) private var allTasks: [Task]
    @Query private var allDayRecords: [DayRecord]

    private var dayRecord: DayRecord? {
        allDayRecords.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    var body: some View {
        ScrollView {
            DayPageContent(date: date, dayRecord: dayRecord, allTasks: allTasks)
                .padding(.vertical)
        }
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

// MARK: - Add timesheet sheet

private struct AddTimesheetSheet: View {
    let date: Date
    let projects: [Project]
    let onSave: (String, Duration?, Project?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var durationText = ""
    @State private var durationError = false
    @State private var selectedProject: Project?

    var body: some View {
        NavigationStack {
            Form {
                Section("Time Entry") {
                    TextField("Description", text: $text)
                    HStack {
                        TextField("Duration (e.g. 1.5h, 2d)", text: $durationText)
                            .onChange(of: durationText) { _, _ in durationError = false }
                        if durationError {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                    Text("Units: h (hours), d (days ≈7.6h), w (weeks ≈38h)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Links") {
                    Picker("Project", selection: $selectedProject) {
                        Text("None").tag(Optional<Project>.none)
                        ForEach(projects) { p in
                            Text(p.name).tag(Optional(p))
                        }
                    }
                }
            }
            .navigationTitle("Add Timesheet Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty && durationText.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 280)
        #endif
    }

    private func save() {
        var parsed: Duration?
        let trimmed = durationText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            guard let d = Duration.parse(trimmed) else {
                durationError = true
                return
            }
            parsed = d
        }
        onSave(text, parsed, selectedProject)
        dismiss()
    }
}

#Preview {
    DiaryView()
        .modelContainer(for: [Task.self, DayRecord.self, DayEntry.self, Project.self,
                               Person.self, Institution.self, Minutes.self],
                        inMemory: true)
        .frame(width: 600, height: 700)
}
