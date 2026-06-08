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

// Intercepts the Escape key to deactivate the currently focused inline field.
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

// Monitors leftMouseDown and calls action when the click lands outside an NSTextView.
// Saves the focused ID before clearing so button actions can restore it after mouseUp.
private final class FocusClearMonitor: @unchecked Sendable {
    private var monitor: Any?
    var action: (() -> Void)?
    var captureId: (() -> UUID?)?
    private(set) var lastClearedId: UUID? = nil

    func consumeLastClearedId() -> UUID? {
        defer { lastClearedId = nil }
        return lastClearedId
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self,
                  let action = self.action,
                  let hit = NSApp.keyWindow?.contentView?.hitTest(event.locationInWindow),
                  !(hit is NSTextView) else { return event }
            self.lastClearedId = self.captureId?()
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
    var showTaskSections: Bool = true
    var onShowBanner: (BannerMessage) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @FocusState private var focusedEntryId: UUID?
    @State private var pendingFocusId: UUID?
    @State private var showingAddTask = false
    @State private var editingTask: Task?
    @State private var editingDocument: Document?
    @State private var editingNote: Note?
    @State private var collapsedTaskIds: Set<UUID> = []
    @State private var collapsedMeetingIds: Set<UUID> = []
    @State private var notesDropTargetIndex: Int?
    @State private var pendingFocusNoteId: UUID?

    @Query(sort: \TaskTimeEntry.date, order: .reverse) private var allTimeEntries: [TaskTimeEntry]

    private var todayTimeEntries: [TaskTimeEntry] {
        let cal = Calendar.current
        return allTimeEntries.filter { cal.isDate($0.date, inSameDayAs: date) }
    }
    #if os(macOS)
    @State private var deleteMonitor = DeleteKeyMonitor()
    @State private var focusClearMonitor = FocusClearMonitor()
    @State private var escapeMonitor = EscapeKeyMonitor()
    #endif

    private var dayStart: Date { DayTaskFiltering.dayBounds(for: date).dayStart }
    private var dayEnd: Date { DayTaskFiltering.dayBounds(for: date).dayEnd }

    // All root tasks for this day record, regardless of status. Status changes alter
    // visual appearance only; tasks don't leave the day they were created for.
    private var newTasks: [Task] {
        (dayRecord?.tasks ?? [])
            .filter { $0.parent == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    // Tasks completed today that are NOT already shown in newTasks.
    // Checks status == .completed because completedAt now persists through cycling.
    private var completedTasks: [Task] {
        let dayTaskIds = Set((dayRecord?.tasks ?? []).map(\.id))
        return allTasks.filter {
            guard let at = $0.completedAt, $0.status == .completed else { return false }
            return at >= dayStart && at < dayEnd && !dayTaskIds.contains($0.id)
        }.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    private var dayMeetings: [DayEntry] {
        (dayRecord?.entries ?? [])
            .filter { $0.kind == .meeting }
            .sorted { ($0.minutes?.meetingAt ?? .distantPast) < ($1.minutes?.meetingAt ?? .distantPast) }
    }

    private var dayDocuments: [Document] {
        (dayRecord?.documents ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    private var dayNotes: [Note] {
        (dayRecord?.noteItems ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    // Tasks scheduled for the sidebar section (excludes tasks already in newTasks).
    private var scheduled: [Task] {
        let dayTaskIds = Set((dayRecord?.tasks ?? []).map(\.persistentModelID))
        return DayTaskFiltering.scheduledTasks(
            allTasks: allTasks, dayStart: dayStart, dayEnd: dayEnd, taskEntryIds: dayTaskIds)
    }

    private var inbox: [Task] {
        DayTaskFiltering.inboxTasks(allTasks: allTasks)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ActivitySection(dayRecord: dayRecord, date: date, todayEntries: todayTimeEntries, meetings: dayMeetings, findOrCreateDayRecord: findOrCreateDayRecord)
                meetingsSection
                newTasksSection
                completedTasksSection
                documentsSection
                notesSection
                if showTaskSections { sidebarSections }
            }
        }
        .sheet(isPresented: $showingAddTask) {
            TaskEditorSheet(task: nil, defaultDate: date) { newTask in
                let record = findOrCreateDayRecord()
                newTask.dayRecord = record
                newTask.sortOrder = nextTaskSortOrder(record)
            }
        }
        .sheet(item: $editingTask) { task in
            TaskEditorSheet(task: task, defaultDate: date)
        }
        .sheet(item: $editingDocument) { doc in
            DocumentDetailView(document: doc, asSheet: true)
        }
        .sheet(item: $editingNote) { n in
            NoteEditorSheet(note: n)
        }
        .onChange(of: pendingFocusId) { _, newId in
            if let id = newId {
                focusedEntryId = id
                pendingFocusId = nil
            }
        }
        .onAppear {
            migrateOldNotes()
            migrateDayNote()
            migrateNoteBlocks()
        }
        #if os(macOS)
        .onAppear {
            deleteMonitor.start()
            focusClearMonitor.captureId = { focusedEntryId }
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
        }
        #endif
    }

    // MARK: - Sections

    @ViewBuilder
    private var notesSection: some View {
        DaySectionHeader(title: "Notes", onAdd: addNote)
        notesDropZone(belowIndex: -1)
        ForEach(Array(dayNotes.enumerated()), id: \.element.id) { idx, note in
            noteRow(note: note, index: idx)
                .draggable(note.id.uuidString)
            notesDropZone(belowIndex: idx)
        }
    }

    @ViewBuilder
    private var meetingsSection: some View {
        DaySectionHeader(title: "Meetings", onAdd: addMeeting)
        ForEach(Array(dayMeetings.enumerated()), id: \.element.id) { idx, entry in
            meetingRow(entry: entry, index: idx)
        }
    }

    @ViewBuilder
    private var newTasksSection: some View {
        DaySectionHeader(title: "New Tasks", onAdd: { showingAddTask = true })
        if newTasks.isEmpty {
            Text("No tasks for this day.")
                .foregroundStyle(.tertiary)
                .font(.callout)
                .padding(.horizontal)
                .padding(.vertical, 4)
        } else {
            ForEach(Array(newTasks.enumerated()), id: \.element.id) { idx, task in
                taskRow(task: task, index: idx)
            }
        }
    }

    @ViewBuilder
    private var completedTasksSection: some View {
        if !completedTasks.isEmpty {
            DaySectionHeader(title: "Completed")
            ForEach(completedTasks) { task in
                CompletedTaskRow(task: task, onEdit: { _ in editingTask = task })
            }
        }
    }

    @ViewBuilder
    private var documentsSection: some View {
        DaySectionHeader(title: "Documents", onAdd: addDocument)
        ForEach(dayDocuments) { doc in
            DayDocumentRow(document: doc, onEdit: { editingDocument = doc })
                .onTapGesture { editingDocument = doc }
                .contextMenu {
                    Button("Edit…") { editingDocument = doc }
                    Button("Delete", role: .destructive) { modelContext.delete(doc) }
                }
        }
    }

    @ViewBuilder
    private var sidebarSections: some View {
        if !scheduled.isEmpty {
            SectionHeader(title: "Scheduled")
            ForEach(scheduled) { task in
                TaskRowView(task: task, onEdit: { editingTask = task })
            }
        }

        let inboxTasks = inbox
        if !inboxTasks.isEmpty {
            SectionHeader(title: "Inbox")
            ForEach(inboxTasks) { task in
                TaskRowView(task: task, onEdit: { editingTask = task })
            }
        }
    }

    // MARK: - Row builders

    private func meetingRow(entry: DayEntry, index: Int) -> some View {
        let count = dayMeetings.count
        return EntryRowView(
            entry: entry,
            focusedEntryId: $focusedEntryId,
            onMoveToPrevious: index > 0 ? { pendingFocusId = dayMeetings[index - 1].id } : nil,
            onMoveToNext: index < count - 1 ? { pendingFocusId = dayMeetings[index + 1].id } : nil,
            isCollapsed: collapsedMeetingIds.contains(entry.id),
            onToggleCollapse: {
                if collapsedMeetingIds.contains(entry.id) { collapsedMeetingIds.remove(entry.id) }
                else { collapsedMeetingIds.insert(entry.id) }
            },
            isNotesFocused: focusedEntryId == entry.notesAreaFocusId,
            onMoveToNextFromNotes: index < count - 1 ? { pendingFocusId = dayMeetings[index + 1].id } : nil,
            onRemoveFromMeeting: { task in
                let record = findOrCreateDayRecord()
                task.originMinutes = nil
                task.dayRecord = record
                task.sortOrder = nextTaskSortOrder(record)
            },
            onDropExternalOntoMeetingTask: { uuidString, targetTask in
                guard let id = UUID(uuidString: uuidString),
                      let dragged = findAnyTask(id: id),
                      dragged.id != targetTask.id else { return false }
                dragged.parent = targetTask
                dragged.dayRecord = nil
                dragged.originMinutes = entry.minutes
                return true
            }
        )
    }

    private func taskRow(task: Task, index: Int) -> some View {
        let count = newTasks.count
        return DiaryTaskRow(
            task: task,
            focusedEntryId: $focusedEntryId,
            isCollapsed: collapsedTaskIds.contains(task.id),
            onToggleCollapse: {
                if collapsedTaskIds.contains(task.id) { collapsedTaskIds.remove(task.id) }
                else { collapsedTaskIds.insert(task.id) }
            },
            onMoveToPrevious: index > 0 ? { pendingFocusId = newTasks[index - 1].id } : nil,
            onMoveToNext: index < count - 1 ? { pendingFocusId = newTasks[index + 1].id } : nil,
            onMoveToNextFromNotes: index < count - 1 ? { pendingFocusId = newTasks[index + 1].id } : nil,
            onDropOntoTask: { uuidString in
                guard let id = UUID(uuidString: uuidString),
                      let dragged = findAnyTask(id: id),
                      dragged.id != task.id else { return false }
                dragged.parent = task
                dragged.dayRecord = nil
                dragged.originMinutes = nil
                return true
            },
            onExternalDropOntoSubtask: { uuidString, targetTask in
                guard let id = UUID(uuidString: uuidString),
                      let dragged = findAnyTask(id: id),
                      dragged.id != targetTask.id else { return false }
                dragged.parent = targetTask
                dragged.dayRecord = nil
                dragged.originMinutes = nil
                return true
            },
            onExternalDropIntoSubtree: { uuidString in
                guard let id = UUID(uuidString: uuidString),
                      let dragged = findAnyTask(id: id),
                      dragged.id != task.id else { return false }
                dragged.parent = task
                dragged.dayRecord = nil
                dragged.originMinutes = nil
                return true
            }
        )
    }

    // MARK: - Helpers

    private func findMeetingTask(id: UUID) -> Task? {
        func search(_ tasks: [Task]) -> Task? {
            for task in tasks {
                if task.id == id { return task }
                if let found = search(task.children) { return found }
            }
            return nil
        }
        for entry in dayMeetings {
            if let found = search(entry.minutes?.newTasks ?? []) { return found }
        }
        return nil
    }

    private func findAnyTask(id: UUID) -> Task? {
        func search(_ list: [Task]) -> Task? {
            for t in list {
                if t.id == id { return t }
                if let found = search(t.children) { return found }
            }
            return nil
        }
        if let found = search(newTasks) { return found }
        for entry in dayMeetings {
            if let found = search(entry.minutes?.newTasks ?? []) { return found }
        }
        return nil
    }

    private func findOrCreateDayRecord() -> DayRecord {
        if let existing = dayRecord { return existing }
        let record = DayRecord(date: date)
        modelContext.insert(record)
        return record
    }

    private func nextTaskSortOrder(_ record: DayRecord) -> Int {
        (record.tasks.filter { $0.parent == nil }.map(\.sortOrder).max() ?? -1) + 1
    }

    private func nearestQuarterHour(on day: Date) -> Date {
        let quarterHour = 15.0 * 60.0
        let now = Date()
        let interval = now.timeIntervalSinceReferenceDate
        let rounded = (interval / quarterHour).rounded() * quarterHour
        let roundedNow = Date(timeIntervalSinceReferenceDate: rounded)
        let cal = Calendar.current
        let hour = cal.component(.hour, from: roundedNow)
        let minute = cal.component(.minute, from: roundedNow)
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    private func addMeeting() {
        let record = findOrCreateDayRecord()
        let meeting = Minutes(meetingAt: nearestQuarterHour(on: date))
        modelContext.insert(meeting)
        let entry = DayEntry(kind: .meeting, text: "",
                             sortOrder: (record.entries.map(\.sortOrder).max() ?? -1) + 1)
        entry.minutes = meeting
        entry.dayRecord = record
        modelContext.insert(entry)
        pendingFocusId = entry.id
    }

    private func addDocument() {
        let record = findOrCreateDayRecord()
        let doc = Document()
        doc.dayRecord = record
        modelContext.insert(doc)
        editingDocument = doc
    }

    private func addNote() {
        let record = findOrCreateDayRecord()
        let note = Note(
            content: "",
            sortOrder: (record.noteItems.map(\.sortOrder).max() ?? -1) + 1
        )
        note.dayRecord = record
        modelContext.insert(note)
        pendingFocusNoteId = note.id
    }

    private func noteRow(note: Note, index: Int) -> some View {
        let count = dayNotes.count
        return DayNoteRow(
            note: note,
            focusedEntryId: $focusedEntryId,
            onMoveToPrevious: index > 0 ? {
                let prev = dayNotes[index - 1]
                pendingFocusId = prev.blocks.last(where: { $0.kind == .text })?.id ?? prev.id
            } : nil,
            onMoveToNext: index < count - 1 ? {
                let next = dayNotes[index + 1]
                pendingFocusId = next.blocks.first(where: { $0.kind == .text })?.id ?? next.id
            } : nil,
            onEdit: { editingNote = note },
            onHeaderButtonTap: {
                guard let savedId = focusClearMonitor.consumeLastClearedId() else { return }
                focusedEntryId = savedId
            },
            onDelete: {
                let i = dayNotes.firstIndex(where: { $0.id == note.id })
                if let i, i > 0 {
                    let prev = dayNotes[i - 1]
                    pendingFocusId = prev.blocks.last(where: { $0.kind == .text })?.id ?? prev.id
                }
                modelContext.delete(note)
            }
        )
        .onAppear {
            guard pendingFocusNoteId == note.id else { return }
            pendingFocusNoteId = nil
            pendingFocusId = note.blocks.first(where: { $0.kind == .text })?.id
        }
    }

    private func notesDropZone(belowIndex: Int) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: 4)
            .dropDestination(for: String.self) { items, _ in
                guard let s = items.first else { return false }
                reorderNote(draggedIdString: s, belowIndex: belowIndex)
                return true
            } isTargeted: { targeted in
                notesDropTargetIndex = targeted ? belowIndex : nil
            }
            .overlay {
                if notesDropTargetIndex == belowIndex {
                    Color.accentColor.frame(height: 2)
                }
            }
    }

    private func reorderNote(draggedIdString: String, belowIndex: Int) {
        guard let id = UUID(uuidString: draggedIdString),
              let fromIdx = dayNotes.firstIndex(where: { $0.id == id }) else { return }
        let targetInsert = belowIndex + 1
        var reordered = dayNotes
        let note = reordered.remove(at: fromIdx)
        var adjusted = fromIdx < targetInsert ? targetInsert - 1 : targetInsert
        adjusted = max(0, min(adjusted, reordered.count))
        reordered.insert(note, at: adjusted)
        for (i, n) in reordered.enumerated() { n.sortOrder = i }
    }

    // Converts Note.content + image attachments → NoteBlock array on first open.
    // Also strips any legacy inline image links that may still be in content.
    private func migrateNoteBlocks() {
        for note in dayRecord?.noteItems ?? [] {
            // Strip leftover inline image links regardless of block migration state
            let stripped = note.content
                .replacingOccurrences(
                    of: #"\n?!\[[^\]]*\]\([^)]+\)"#,
                    with: "", options: .regularExpression
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Already has blocks — just clean up legacy inline links if needed
            if !note.blocks.isEmpty {
                if stripped != note.content {
                    note.content = stripped
                    note.updatedAt = Date()
                }
                continue
            }

            // Build blocks from legacy content + image attachments
            var blocks: [NoteBlock] = [.text(stripped)]
            let images = note.attachments
                .filter { $0.kind == .image }
                .sorted { $0.createdAt < $1.createdAt }
            for img in images {
                blocks.append(.image(img.id))
                blocks.append(.text(""))
            }
            note.blocks = blocks
            note.content = ""
            note.updatedAt = Date()
        }
    }

    private func migrateDayNote() {
        guard let record = dayRecord,
              let text = record.notes,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let note = Note(content: text, sortOrder: 0)
        note.dayRecord = record
        modelContext.insert(note)
        record.notes = nil
    }

    // Concatenates old DayEntry(kind:.note) entries into DayRecord.notes and deletes them.
    private func migrateOldNotes() {
        let noteEntries = (dayRecord?.entries ?? []).filter { $0.kind == .note }
        guard !noteEntries.isEmpty else { return }
        let text = noteEntries
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        if !text.isEmpty {
            let record = findOrCreateDayRecord()
            let existing = (record.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            record.notes = existing.isEmpty ? text : existing + "\n\n" + text
        }
        noteEntries.forEach { modelContext.delete($0) }
    }

    #if os(macOS)
    private func updateDeleteAction(for focusId: UUID?) {
        guard let focusId else { deleteMonitor.action = nil; return }
        if let task = newTasks.first(where: { $0.id == focusId }) {
            deleteMonitor.action = {
                guard task.isInlineSummaryEmpty else { return false }
                let idx = newTasks.firstIndex(where: { $0.id == focusId })
                if let i = idx, i > 0 { pendingFocusId = newTasks[i - 1].id }
                modelContext.delete(task)
                return true
            }
        } else if let entry = dayMeetings.first(where: { $0.id == focusId }) {
            deleteMonitor.action = {
                guard entry.isInlineSummaryEmpty else { return false }
                if let m = entry.minutes { modelContext.delete(m) }
                modelContext.delete(entry)
                return true
            }
        } else if let note = dayNotes.first(where: { n in
            n.id == focusId || n.blocks.contains(where: { $0.id == focusId })
        }) {
            deleteMonitor.action = {
                let allTextEmpty = note.blocks.filter { $0.kind == .text }
                    .allSatisfy { $0.textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                let hasImages = note.blocks.contains(where: { $0.kind == .image })
                guard allTextEmpty && !hasImages else { return false }
                let idx = dayNotes.firstIndex(where: { $0.id == note.id })
                if let i = idx, i > 0 {
                    let prev = dayNotes[i - 1]
                    pendingFocusId = prev.blocks.last(where: { $0.kind == .text })?.id ?? prev.id
                }
                modelContext.delete(note)
                return true
            }
        } else {
            deleteMonitor.action = nil
        }
    }
    #endif
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
    @State private var inboxExpanded = true
    @State private var pendingStatusIds: Set<UUID> = []

    private var dayStart: Date { DayTaskFiltering.dayBounds(for: date).dayStart }
    private var dayEnd: Date { DayTaskFiltering.dayBounds(for: date).dayEnd }

    private var dayTaskIds: Set<PersistentIdentifier> {
        Set((dayRecord?.tasks ?? []).map(\.persistentModelID))
    }

    private var scheduled: [Task] {
        let base = DayTaskFiltering.scheduledTasks(
            allTasks: allTasks, dayStart: dayStart, dayEnd: dayEnd, taskEntryIds: dayTaskIds)
        let baseIds = Set(base.map(\.id))
        let held = allTasks.filter { pendingStatusIds.contains($0.id) && !baseIds.contains($0.id) }
        return (base + held).sorted { ($0.scheduledAt ?? .distantPast) < ($1.scheduledAt ?? .distantPast) }
    }

    private var inbox: [Task] {
        let base = DayTaskFiltering.inboxTasks(allTasks: allTasks)
        let baseIds = Set(base.map(\.id))
        let held = allTasks.filter { pendingStatusIds.contains($0.id) && !baseIds.contains($0.id) }
        return base + held
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !scheduled.isEmpty {
                    sectionHeader("Scheduled", expanded: $scheduledExpanded)
                    if scheduledExpanded {
                        ForEach(scheduled) { task in
                            TaskRowView(
                                task: task,
                                onEdit: { editingTask = task },
                                onBeforeStatusChange: {
                                    if task.status == .started { pendingStatusIds.insert(task.id) }
                                }
                            )
                            .opacity(pendingStatusIds.contains(task.id) ? 0.5 : 1.0)
                        }
                        .animation(.easeInOut(duration: 0.25), value: scheduled.map(\.id))
                    }
                }

                sectionHeader("Inbox", expanded: $inboxExpanded)
                if inboxExpanded {
                    if inbox.isEmpty {
                        Text("No unassigned tasks.")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(inbox) { task in
                            TaskRowView(
                                task: task,
                                onEdit: { editingTask = task },
                                onBeforeStatusChange: {
                                    if task.status == .started { pendingStatusIds.insert(task.id) }
                                }
                            )
                            .opacity(pendingStatusIds.contains(task.id) ? 0.5 : 1.0)
                        }
                        .animation(.easeInOut(duration: 0.25), value: inbox.map(\.id))
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .onChange(of: date) { pendingStatusIds.removeAll() }
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
                               Person.self, Institution.self, Minutes.self,
                               FocusBlock.self, TaskTimeEntry.self],
                        inMemory: true)
        .frame(width: 600, height: 700)
}
