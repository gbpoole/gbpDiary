import SwiftUI
import SwiftData

// MARK: - Shared banner message type

struct BannerMessage: Equatable {
    let text: String
    let systemImage: String
    let tint: Color

    init(text: String, systemImage: String, tint: Color) {
        self.text = text; self.systemImage = systemImage; self.tint = tint
    }

    /// Convenience for transient info/error banners.
    init(text: String, isError: Bool = false) {
        self.text = text
        self.systemImage = isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        self.tint = isError ? AppTheme.destructive : AppTheme.accent
    }
}

// MARK: - Shared day content (used by DayView and WeekView)

struct DayPageContent: View {
    let date: Date
    var dayRecord: DayRecord?
    let allTasks: [Task]
    var showTaskSections: Bool = true
    var showActionBar: Bool = true
    var onShowBanner: (BannerMessage) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @Environment(DiaryState.self) private var diaryState: DiaryState?
    @State private var showingAddTask = false
    @State private var activityMeetingTrigger = false
    @State private var activityLogTimeTrigger = false
    @State private var activityFocusBlockTrigger = false
    @State private var editingTask: Task?
    @State private var editingNote: Note?
    @State private var notesDropTargetIndex: Int?
    @State private var newlyAddedNoteId: UUID?
    @State private var addNoteRecord: DayRecord?

    @Query(sort: \TaskTimeEntry.date, order: .reverse) private var allTimeEntries: [TaskTimeEntry]
    @Query(sort: \EmailMessage.date, order: .reverse) private var allEmails: [EmailMessage]
    @Query private var allPeople: [Person]
    @State private var showingTriage = false
    @State private var reconcilingThread: EmailThread?

    private var todayTimeEntries: [TaskTimeEntry] {
        let cal = Calendar.current
        return allTimeEntries.filter { cal.isDate($0.date, inSameDayAs: date) }
    }

    // Emails for the day grouped into threads (same normalized subject + other party), latest first.
    private var dayEmailThreads: [EmailThread] {
        let groups = Dictionary(grouping: dayEmails) { email in
            EmailThreading.threadKey(subject: email.subject,
                                     party: email.person?.id.uuidString ?? email.fromAddress)
        }
        return groups.map { key, msgs in
            EmailThread(key: key, messages: msgs.sorted { $0.date > $1.date })
        }
        .sorted { $0.date > $1.date }
    }

    // Sent emails for the day (shown in the Activity section at their send time).
    private var daySentEmails: [EmailMessage] {
        dayEmails.filter { $0.direction == .sent }
    }

    // Only accepted emails reach the diary; unclassified ones wait in the triage window.
    private var dayEmails: [EmailMessage] {
        let cal = Calendar.current
        return allEmails.filter { cal.isDate($0.date, inSameDayAs: date) && $0.triageState == .accepted }
    }

    private func dayEmailCount(_ state: EmailTriageState) -> Int {
        let cal = Calendar.current
        return allEmails.filter { cal.isDate($0.date, inSameDayAs: date) && $0.triageState == state }.count
    }
    private var dayUnclassifiedCount: Int { dayEmailCount(.unclassified) }
    private var dayDismissedCount: Int { dayEmailCount(.dismissed) }

    // A "N to triage · M dismissed" summary of this day's hidden (non-accepted) emails, or nil if none.
    private var hiddenEmailSummary: String? {
        var parts: [String] = []
        if dayUnclassifiedCount > 0 { parts.append("\(dayUnclassifiedCount) to triage") }
        if dayDismissedCount > 0 { parts.append("\(dayDismissedCount) dismissed") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

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

    private var activityCompletedTasks: [Task] {
        let dayTaskIds = Set((dayRecord?.tasks ?? []).map(\.id))
        return allTasks.filter { task in
            guard let at = task.completedAt,
                  task.status == .completed,
                  at >= dayStart && at < dayEnd,
                  !dayTaskIds.contains(task.id),
                  task.duration != nil,
                  task.timeEntries.isEmpty else { return false }
            return true
        }.sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
    }

    private var dayMeetings: [DayEntry] {
        (dayRecord?.entries ?? [])
            .filter { $0.kind == .meeting }
            .sorted { ($0.minutes?.meetingAt ?? .distantPast) < ($1.minutes?.meetingAt ?? .distantPast) }
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

    // Mirrors ActivitySection.canAddBlock — evening is always addable; otherwise no more slots if
    // allDay is taken, or both morning and afternoon are already filled.
    private var canAddFocusBlock: Bool {
        let taken = Set((dayRecord?.focusBlocks ?? []).map(\.slot))
        if !taken.contains(.evening) { return true }
        if taken.contains(.allDay) { return false }
        return !taken.contains(.morning) || !taken.contains(.afternoon)
    }

    /// Platform-agnostic action list. macOS renders this as DayActionBar;
    /// iOS will render the same list as a FAB (future).
    private var actionItems: [DayActionItem] {
        [
            DayActionItem(id: "focusblock", systemName: "scope",               color: AppTheme.tag,       tooltip: "Add focus block", isEnabled: canAddFocusBlock) { activityFocusBlockTrigger = true },
            DayActionItem(id: "meeting",    systemName: "calendar.badge.plus", color: AppTheme.project,   tooltip: "Add meeting")     { activityMeetingTrigger = true },
            DayActionItem(id: "logtime",    systemName: "timer",               color: AppTheme.duration,  tooltip: "Log time")        { activityLogTimeTrigger = true },
            DayActionItem(id: "task",       systemName: "checkmark.square",    color: AppTheme.completed, tooltip: "Add task")        { showingAddTask = true },
            DayActionItem(id: "note",       systemName: "square.and.pencil",   color: AppTheme.accent,    tooltip: "Add note")        { addNote() },
            DayActionItem(id: "email",      systemName: "tray.full",           color: AppTheme.person,    tooltip: "Triage email") { showingTriage = true },
        ]
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if showActionBar {
                        DayActionBar(items: actionItems)
                    }
                    ActivitySection(
                        dayRecord: dayRecord,
                        date: date,
                        todayEntries: todayTimeEntries,
                        meetings: dayMeetings,
                        completedTasks: activityCompletedTasks,
                        sentEmails: daySentEmails,
                        findOrCreateDayRecord: findOrCreateDayRecord,
                        logTimeTrigger: $activityLogTimeTrigger,
                        focusBlockTrigger: $activityFocusBlockTrigger,
                        meetingTrigger: $activityMeetingTrigger
                    )
                    newTasksSection
                    completedTasksSection
                    notesSection
                    emailsSection
                    if showTaskSections { sidebarSections }
                }
                .padding(.vertical, 8)
            }
            .onAppear { scrollToTargetIfNeeded(proxy) }
            .onChange(of: diaryState?.scrollTargetNoteId) { scrollToTargetIfNeeded(proxy) }
        }
        .background(AppTheme.background)
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
        .sheet(item: $editingNote) { n in
            NoteEditorSheet(note: n)
        }
        .sheet(item: $addNoteRecord) { record in
            ContentNoteEditorSheet(dayRecord: record, onCreated: { newlyAddedNoteId = $0.id })
        }
        .sheet(isPresented: $showingTriage) { EmailTriageSheet(day: date) }
        .sheet(item: $reconcilingThread) { thread in
            ResolveAttendeeSheet(
                attendee: CalendarAttendee(name: thread.fromName ?? "", email: thread.fromAddress),
                onResolve: { resolveEmailPerson(thread, $0) }
            )
        }
        .onAppear {
            migrateOldNotes()
            migrateDayNote()
        }
    }

    // MARK: - Email

    @ViewBuilder private var emailsSection: some View {
        DaySectionHeader(title: "Email")
        // Hidden (non-accepted) emails for this day — tap to open the triage window.
        if let hidden = hiddenEmailSummary {
            Button { showingTriage = true } label: {
                Label(hidden, systemImage: "tray.full")
                    .font(.caption).foregroundStyle(AppTheme.accent)
            }
            .buttonStyle(.plain)
            .padding(.horizontal).padding(.vertical, 4)
        }
        // If summaries can't run (Apple Intelligence off / model downloading), tell the user why.
        if !dayEmails.isEmpty, dayEmails.contains(where: { $0.summaryState == EmailSummaryState.pending.rawValue }),
           let reason = FoundationModelsSummarizer().unavailableReason {
            Label(reason, systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.vertical, 4)
        }
        if dayEmails.isEmpty {
            Text(hiddenEmailSummary == nil ? "No emails for this day." : "No emails on the diary for this day.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .padding(.horizontal)
                .padding(.vertical, 6)
        } else {
            ForEach(dayEmailThreads) { thread in
                DayEmailThreadRow(thread: thread, onReconcile: { reconcilingThread = thread })
            }
        }
    }

    // Resolve the thread's other party (link/create a Person) and apply to every message in it.
    private func resolveEmailPerson(_ thread: EmailThread, _ result: AttendeeReconcileResult) {
        let person: Person
        switch result {
        case .link(let p):
            if !thread.fromAddress.isEmpty { p.emails = Person.appendingEmail(thread.fromAddress, to: p.emails) }
            p.updatedAt = Date()
            person = p
        case .create(let name, let inst):
            let p = Person(name: name)
            if !thread.fromAddress.isEmpty { p.emails = [thread.fromAddress] }
            p.institution = inst
            modelContext.insert(p)
            person = p
        }
        for message in thread.messages { message.person = person }
    }

    // MARK: - Sections

    @ViewBuilder
    private var notesSection: some View {
        if !dayNotes.isEmpty {
            DaySectionHeader(title: "Notes")
            notesDropZone(belowIndex: -1)
            ForEach(Array(dayNotes.enumerated()), id: \.element.id) { idx, note in
                noteRow(note: note, index: idx)
                    .draggable(note.id.uuidString)
                notesDropZone(belowIndex: idx)
            }
        }
    }

    @ViewBuilder
    private var newTasksSection: some View {
        if !newTasks.isEmpty {
            DaySectionHeader(title: "New Tasks")
            ForEach(newTasks) { task in
                DayTaskActivityRow(task: task, date: date)
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

    // MARK: - Helpers

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

    private func addNote() {
        // Use the same modal as content notes to set title/tags/project up front; the created note
        // is attached to this day and shown in the diary Notes section.
        addNoteRecord = findOrCreateDayRecord()
    }

    private func noteRow(note: Note, index: Int) -> some View {
        MarkdownDocumentEditor(
            note: note,
            onEdit: { editingNote = note },
            onDelete: { modelContext.delete(note) },
            startInEdit: newlyAddedNoteId == note.id
        )
        .padding(.horizontal)
        .padding(.vertical, 2)
        .id(note.id)
    }

    private func scrollToTargetIfNeeded(_ proxy: ScrollViewProxy) {
        guard let target = diaryState?.scrollTargetNoteId,
              dayNotes.contains(where: { $0.id == target }) else { return }
        withAnimation { proxy.scrollTo(target, anchor: .top) }
        diaryState?.scrollTargetNoteId = nil
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

}

// MARK: - Day tab root view

struct DayView: View {
    let date: Date
    let dayRecord: DayRecord?
    let allTasks: [Task]

    @State private var banner: BannerMessage? = nil

    var body: some View {
        // The date is shown once, in the diary bar above. DayPageContent has its own ScrollView and
        // leads with the action bar, so the add-activity buttons sit at the top of the page.
        DayPageContent(date: date, dayRecord: dayRecord, allTasks: allTasks,
                       showTaskSections: false,
                       onShowBanner: showBanner)
            .overlay(alignment: .bottom) {
                if let msg = banner { bannerView(msg) }
            }
            .animation(.easeInOut(duration: 0.25), value: banner)
    }

    private func showBanner(_ msg: BannerMessage) {
        banner = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { banner = nil }
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

// MARK: - Day task activity row (New Tasks section)

private final class DayTaskActivityTapFlags { var didTapStatus = false; var didTapAddTime = false }

struct DayTaskActivityRow: View {
    var task: Task
    var date: Date

    @Environment(\.modelContext) private var modelContext
    @State private var showingEdit = false
    @State private var showingAddTime = false
    @State private var tapFlags = DayTaskActivityTapFlags()
    @State private var tapCount = 0

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Color.clear.frame(width: 16, height: 1)
                .sheet(isPresented: $showingAddTime) {
                    LogTimeSheet(presetTask: task, presetDate: date)
                }

            HStack(alignment: .center, spacing: 6) {
                statusIconView

                Text(task.summary)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.text)

                Spacer(minLength: 8)

                HStack(spacing: 4) {
                    addTimeIconView
                        .frame(width: 24, alignment: .center)
                    Group {
                        if let project = task.project {
                            Chip(label: project.name, color: AppTheme.project)
                        }
                    }
                    Group {
                        if let dur = task.loggedDuration {
                            Chip(label: dur.displayString, color: AppTheme.duration)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.cardRaised.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { tapCount += 1 })
            .onChange(of: tapCount) {
                if tapFlags.didTapStatus || tapFlags.didTapAddTime {
                    tapFlags.didTapStatus = false
                    tapFlags.didTapAddTime = false
                } else {
                    showingEdit = true
                }
            }
            .padding(.trailing)
            .sheet(isPresented: $showingEdit) {
                TaskEditorSheet(task: task, defaultDate: date)
            }
            .contextMenu {
                if task.status != .completed {
                    Button("Mark Complete") { task.markCompleted() }
                }
                if task.status == .todo || task.status == .cancelled {
                    Button("Mark Started") { task.status = .started; task.updatedAt = Date() }
                }
                if task.status == .completed || task.status == .cancelled || task.status == .followUpPending {
                    Button("Reopen") {
                        if task.status == .cancelled { task.unmarkCancelled() } else { task.unmarkCompleted() }
                    }
                }
                Divider()
                Button("Delete", role: .destructive) { modelContext.delete(task) }
            }
        }
        .padding(.leading)
        .padding(.vertical, 1)
        .onChange(of: showingAddTime) { _, isShowing in
            if !isShowing, task.status == .todo, !task.timeEntries.isEmpty {
                task.status = .started
                task.updatedAt = Date()
            }
        }
    }

    @ViewBuilder
    private var addTimeIconView: some View {
        if task.status == .todo || task.status == .started {
            Button {
                tapFlags.didTapAddTime = true
                showingAddTime = true
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.action)
            }
            .buttonStyle(.plain)
            .help("Log time")
        }
    }

    @ViewBuilder
    private var statusIconView: some View {
        Button {
            tapFlags.didTapStatus = true
            toggleStatus(task)
        } label: {
            Image(systemName: taskStatusIcon(task))
                .font(.system(size: 12))
                .foregroundStyle(taskStatusColor(task))
                .frame(width: 18)
        }
        .buttonStyle(.plain)
    }

    private func toggleStatus(_ task: Task) {
        switch task.status {
        case .todo:            task.status = .started; task.updatedAt = Date()
        case .started:         task.markCompleted()
        case .completed:       task.markCancelled()
        case .followUpPending: task.markCancelled()
        case .cancelled:       task.unmarkCancelled()
        }
    }

    private func taskStatusIcon(_ task: Task) -> String {
        switch task.status {
        case .todo:            return "circle"
        case .started:         return "play.circle.fill"
        case .completed:       return "checkmark.circle.fill"
        case .cancelled:       return "xmark.circle.fill"
        case .followUpPending: return "arrow.clockwise.circle.fill"
        }
    }

    private func taskStatusColor(_ task: Task) -> Color {
        switch task.status {
        case .todo:            return AppTheme.mutedText
        case .started:         return AppTheme.started
        case .completed:       return AppTheme.completed
        case .cancelled:       return AppTheme.mutedText
        case .followUpPending: return AppTheme.followUp
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
