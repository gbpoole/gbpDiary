import SwiftUI
import SwiftData

struct ActivitySection: View {
    @Query(sort: \FocusBlock.sortOrder) private var allFocusBlocks: [FocusBlock]
    @Environment(\.modelContext) private var modelContext

    var dayRecord: DayRecord?
    var date: Date
    var todayEntries: [TaskTimeEntry]   // the day's time entries — task-, email-, and conversation-linked
    var meetings: [DayEntry] = []
    var completedTasks: [Task] = []
    // Lazily creates the DayRecord for `date` if it does not exist yet.
    var findOrCreateDayRecord: (() -> DayRecord)? = nil
    /// Trigger bindings wired from DayPageContent's action bar.
    /// Default to .constant(false) so callers that don't use the action bar still compile.
    var logTimeTrigger: Binding<Bool> = .constant(false)
    var focusBlockTrigger: Binding<Bool> = .constant(false)
    var meetingTrigger: Binding<Bool> = .constant(false)

    @State private var showingAddFocusBlock = false
    @State private var showingLogTime = false
    @State private var selectedMeetingMinutes: Minutes?
    @State private var isNewMeeting = false
    @State private var editorDayRecord: DayRecord?

    // @Query-driven so new blocks appear immediately without relationship-refresh lag.
    private var blocks: [FocusBlock] {
        guard let id = dayRecord?.id else { return [] }
        return allFocusBlocks.filter { $0.dayRecord?.id == id }
    }

    // Block membership is derived purely from each entry's time — nothing is stored. The block
    // whose range contains the time owns the entry; entries covered by no block are standalone.
    // Task-backed time entries only (email- and conversation-linked entries are shown in the diary
    // Email section instead; their time still reduces a block's net, see emailHours(for:)).
    // Weekday entries only — weekend-dated work (folded onto Friday) is shown separately as an
    // overtime group, not assigned to Friday's focus blocks.
    private var taskEntries: [TaskTimeEntry] {
        todayEntries.filter { $0.email == nil && $0.conversation == nil && !WeekendPolicy.isWeekend($0.date) }
    }

    private func entries(for block: FocusBlock) -> [TaskTimeEntry] {
        taskEntries.filter { FocusBlockAssignment.containingBlock(for: $0.date, blocks: blocks)?.id == block.id }
    }

    // Entries not covered by any block's range — rendered standalone, at block indent level.
    private var standaloneEntries: [TaskTimeEntry] {
        taskEntries.filter { FocusBlockAssignment.containingBlock(for: $0.date, blocks: blocks) == nil }
    }

    // Weekday email/conversation-linked time entries. NOT rendered here (emails live in the diary Email
    // section), but their logged time still reduces the containing block's net remaining.
    private var weekdayEmailEntries: [TaskTimeEntry] {
        todayEntries.filter { ($0.email != nil || $0.conversation != nil) && !WeekendPolicy.isWeekend($0.date) }
    }

    // The email/conversation time (hours) whose send time falls inside this block — reduces its net.
    private func emailHours(for block: FocusBlock) -> Double {
        weekdayEmailEntries
            .filter { FocusBlockAssignment.containingBlock(for: $0.date, blocks: blocks)?.id == block.id }
            .reduce(0.0) { $0 + $1.duration.hoursNormalized }
    }

    // MARK: - Weekend work (folded onto Friday, shown as one overtime group)
    private func isWeekend(_ date: Date) -> Bool { WeekendPolicy.isWeekend(date) }
    private var weekendEntries: [TaskTimeEntry] {
        todayEntries.filter { $0.email == nil && $0.conversation == nil && isWeekend($0.date) }
            .sorted { $0.date < $1.date }
    }
    // Weekend-dated email/conversation time (folded to Friday overtime; not rendered, counted only).
    private var weekendEmailHours: Double {
        todayEntries.filter { ($0.email != nil || $0.conversation != nil) && isWeekend($0.date) }
            .reduce(0.0) { $0 + $1.duration.hoursNormalized }
    }
    private var weekendCompletedTasks: [Task] { completedTasks.filter { $0.completedAt.map(isWeekend) ?? false } }
    private var weekdayCompletedTasks: [Task] { completedTasks.filter { !($0.completedAt.map(isWeekend) ?? false) } }
    private var hasWeekendWork: Bool {
        !weekendEntries.isEmpty || weekendEmailHours > 0 || !weekendCompletedTasks.isEmpty
    }
    private var weekendHours: Double {
        weekendEntries.reduce(0.0) { $0 + $1.duration.hoursNormalized }
            + weekendEmailHours
            + weekendCompletedTasks.compactMap(\.duration).reduce(0.0) { $0 + $1.hoursNormalized }
    }
    @State private var weekendCollapsed = false

    private enum ActivityRowItem: Identifiable {
        case block(FocusBlock)
        case entry(TaskTimeEntry)
        var id: String {
            switch self {
            case .block(let b): "b-\(b.id.uuidString)"
            case .entry(let e): "e-\(e.id.uuidString)"
            }
        }
    }

    // The time a block's range begins, used to order blocks against standalone entries.
    private func slotStart(_ block: FocusBlock) -> Date {
        let cal = Calendar.current
        switch block.slot {
        case .morning, .allDay: return cal.startOfDay(for: date)
        case .afternoon:        return DaySlotBoundary.morningAfternoon(on: date)
        case .evening:          return block.startTime ?? cal.date(bySettingHour: 18, minute: 0, second: 0, of: date) ?? date
        }
    }

    // Blocks + standalone entries, interleaved in chronological order. (Standalone sent emails are
    // collected into a single collapsible group rather than interleaved — see the body.)
    private var activityItems: [ActivityRowItem] {
        let blockItems = blocks.map { (slotStart($0), ActivityRowItem.block($0)) }
        let entryItems = standaloneEntries.map { ($0.date, ActivityRowItem.entry($0)) }
        return (blockItems + entryItems).sorted { $0.0 < $1.0 }.map(\.1)
    }

    private func meetings(for block: FocusBlock) -> [DayEntry] {
        switch block.slot {
        case .allDay:
            return meetings
        case .morning, .afternoon:
            // Only meetings that actually occupy time in this slot — so a meeting spanning 12:30 shows (and
            // counts) in each block by its portion, and one ending exactly at 12:30 isn't a phantom afternoon row.
            return meetings.filter { entry in
                guard let m = entry.minutes, let d = m.duration else { return false }
                return MeetingSlotHours.overlapHours(start: m.meetingAt, durationHours: d.hoursNormalized,
                                                     slot: block.slot, on: date) > 0
            }
        case .evening:
            return []
        }
    }

    // Meetings not already shown inside a FocusBlock, sorted by start time.
    private var standaloneMeetings: [Minutes] {
        let assignedMinutesIds = Set(
            blocks.flatMap { meetings(for: $0) }.compactMap { $0.minutes?.id }
        )
        return meetings
            .compactMap(\.minutes)
            .filter { !assignedMinutesIds.contains($0.id) }
            .sorted { $0.meetingAt < $1.meetingAt }
    }

    // No more slots can be added if an all-day block exists, or both morning and afternoon are taken.
    private var canAddBlock: Bool {
        let taken = Set(blocks.map(\.slot))
        if !taken.contains(.evening) { return true }   // an evening block is always addable
        if taken.contains(.allDay) { return false }
        return !taken.contains(.morning) || !taken.contains(.afternoon)
    }

    var body: some View {
        let hasContent = !blocks.isEmpty || !todayEntries.isEmpty
            || !standaloneMeetings.isEmpty || !completedTasks.isEmpty
            || hasWeekendWork

        activityHeader

        if hasContent {
            // Focus blocks and any standalone (out-of-range) entries, interleaved by time.
            ForEach(activityItems) { item in
                switch item {
                case .block(let block):
                    FocusBlockRow(block: block, date: date, entries: entries(for: block),
                                  meetings: meetings(for: block), emailHours: emailHours(for: block))
                case .entry(let entry):
                    ActivityEntryRow(entry: entry)
                }
            }

            ForEach(standaloneMeetings, id: \.id) { minutes in
                StandaloneMeetingRow(minutes: minutes)
            }

            ForEach(weekdayCompletedTasks) { task in
                CompletedTaskActivityRow(task: task)
            }

            if hasWeekendWork { weekendGroup }
        } else {
            Text("No activity logged for this day.")
                .foregroundStyle(.tertiary)
                .font(.callout)
                .padding(.horizontal)
                .padding(.vertical, 8)
        }

        if let record = editorDayRecord {
            Color.clear
                .frame(width: 0, height: 0)
                .sheet(isPresented: $showingAddFocusBlock, onDismiss: { editorDayRecord = nil }) {
                    FocusBlockEditorSheet(dayRecord: record)
                }
        }

        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: logTimeTrigger.wrappedValue) { _, triggered in
                guard triggered else { return }
                showingLogTime = true
                logTimeTrigger.wrappedValue = false
            }
            .onChange(of: focusBlockTrigger.wrappedValue) { _, triggered in
                guard triggered else { return }
                editorDayRecord = findOrCreateDayRecord?() ?? dayRecord
                showingAddFocusBlock = true
                focusBlockTrigger.wrappedValue = false
            }
            .onChange(of: meetingTrigger.wrappedValue) { _, triggered in
                guard triggered else { return }
                addMeeting()
                meetingTrigger.wrappedValue = false
            }
            .sheet(isPresented: $showingLogTime) {
                LogTimeSheet(presetDate: date)
            }

        Color.clear
            .frame(width: 0, height: 0)
            .sheet(item: $selectedMeetingMinutes) { m in
                MinutesDetailView(minutes: m, asSheet: true, isNew: isNewMeeting)
            }
    }

    // MARK: - Activity header

    // Total and Overtime come from the canonical TimeLedger (the same module Chat + Timesheet use), so the
    // three can never disagree. `standardTotal` reproduces the old formula (standard-block capacity +
    // standalone weekday work); `overtime` is evening in-block + weekend work.
    private var dayLedger: LedgerResult {
        TimeLedgerProjection.diaryLedger(focusBlocks: blocks, taskEntries: todayEntries,
                                         completedTasks: completedTasks,
                                         meetings: meetings.compactMap(\.minutes))
    }
    private var totalHours: Double { dayLedger.standardTotal }
    private var overtimeHours: Double { dayLedger.overtime }

    // Weekend-dated work folded onto Friday: one collapsible group, counted in the Overtime total.
    @ViewBuilder private var weekendGroup: some View {
        Button { weekendCollapsed.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: weekendCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption2).foregroundStyle(.tertiary)
                Text("Weekend").font(.subheadline.bold()).foregroundStyle(AppTheme.accent)
                Text(Duration(value: weekendHours, unit: .h).displayString)
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal).padding(.top, 12).padding(.bottom, 2)
        }
        .buttonStyle(.plain)
        if !weekendCollapsed {
            ForEach(weekendEntries) { entry in ActivityEntryRow(entry: entry) }
            ForEach(weekendCompletedTasks) { task in CompletedTaskActivityRow(task: task) }
        }
    }

    private var activityHeader: some View {
        HStack(spacing: 8) {
            Text("Activity")
                .font(AppTheme.interfaceFont(size: 12, weight: .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(AppTheme.mutedText)
            Spacer()
            if overtimeHours > 0 {
                Text("Overtime \(Duration(value: overtimeHours, unit: .h).displayString)")
                    .font(AppTheme.interfaceFont(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
            }
            if totalHours > 0 {
                Text("Total \(Duration(value: totalHours, unit: .h).displayString)")
                    .font(AppTheme.interfaceFont(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedText)
            }
        }
        .padding(.horizontal)
        .padding(.top, 16)
        .padding(.bottom, 4)
        .background(AppTheme.background)
    }

    // MARK: - Add meeting

    private func addMeeting() {
        let record = findOrCreateDayRecord?() ?? dayRecord
        guard let record else { return }
        let meeting = Minutes(meetingAt: nearestQuarterHour())
        meeting.duration = Duration(value: 1, unit: .h)
        modelContext.insert(meeting)
        let entry = DayEntry(kind: .meeting, text: "",
                             sortOrder: (record.entries.map(\.sortOrder).max() ?? -1) + 1)
        entry.minutes = meeting
        entry.dayRecord = record
        modelContext.insert(entry)
        isNewMeeting = true
        selectedMeetingMinutes = meeting
    }

    private func nearestQuarterHour() -> Date {
        let quarterHour = 15.0 * 60.0
        let now = Date()
        let interval = now.timeIntervalSinceReferenceDate
        let rounded = (interval / quarterHour).rounded() * quarterHour
        let roundedNow = Date(timeIntervalSinceReferenceDate: rounded)
        let cal = Calendar.current
        let hour = cal.component(.hour, from: roundedNow)
        let minute = cal.component(.minute, from: roundedNow)
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
    }

}

// A sent email row with time-logging. Logged time attaches to the owning EmailConversation (which owns email
// time and feeds the canonical ledger), counted toward the block/day. Shown inside an expanded conversation's
// drill-down in the diary Email section.
struct SentEmailActivityRow: View {
    var email: EmailMessage
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.name) private var allProjects: [Project]
    @State private var showingLogTime = false
    @State private var reconciling = false
    @State private var editingProject = false
    @State private var mailService = MailScriptService()
    @State private var openError: String?

    // Email time is owned by the conversation; a message should always be threaded, but fall back to the
    // message itself if not (pre-migration) so logging still works.
    private var conversation: EmailConversation? { email.conversation }

    private var loggedHours: Double {
        let entries = conversation?.timeEntries ?? email.timeEntries
        return entries.reduce(0.0) { $0 + $1.duration.hoursNormalized }
    }

    // One-click accumulate: append a time entry at the email's send time, against the conversation (so it
    // reaches the Chat/Timesheet ledger) — falling back to the message when unthreaded.
    private func logEmailTime(_ minutes: Int) {
        let duration = Duration(value: Double(minutes) / 60.0, unit: .h)
        let entry: TaskTimeEntry
        if let convo = conversation {
            let nextOrder = (convo.timeEntries.map(\.sortOrder).max() ?? -1) + 1
            entry = TaskTimeEntry(date: email.date, duration: duration, comment: nil, sortOrder: nextOrder)
            entry.conversation = convo
        } else {
            let nextOrder = (email.timeEntries.map(\.sortOrder).max() ?? -1) + 1
            entry = TaskTimeEntry(date: email.date, duration: duration, comment: nil, sortOrder: nextOrder)
            entry.email = email
        }
        modelContext.insert(entry)
    }

    private func quickButton(_ label: String, _ minutes: Int) -> some View {
        Button { logEmailTime(minutes) } label: {
            Text(label)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(AppTheme.action.opacity(0.14), in: Capsule())
                .foregroundStyle(AppTheme.action)
        }
        .buttonStyle(.plain)
        .help("Log \(label) for writing this email")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Color.clear.frame(width: 16, height: 1)
            VStack(alignment: .leading, spacing: 3) {
                controlsLine   // editable person/project + time-log actions, grouped together
                EmailContentLine(subject: email.subject, summary: email.summary,
                                 isSummarizing: email.isSummarizing,
                                 font: .subheadline, lineLimit: 2)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardRaised.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .padding(.trailing)
        }
        .padding(.leading)
        .padding(.vertical, 1)
        .contextMenu {
            EmailExperimentInChatButton(email: email)
        }
        .sheet(isPresented: $showingLogTime) {
            if let convo = conversation {
                LogTimeSheet(presetDate: email.date, presetConversation: convo)
            } else {
                LogTimeSheet(presetDate: email.date, presetEmail: email)
            }
        }
        .sheet(isPresented: $reconciling) {
            ResolveAttendeeSheet(
                attendee: CalendarAttendee(name: email.fromName ?? "", email: email.fromAddress),
                onResolve: { resolvePerson($0) }
            )
        }
        .alert("Couldn't open email", isPresented: Binding(get: { openError != nil }, set: { if !$0 { openError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(openError ?? "") }
    }

    // First line: open-in-Mail + editable recipient/project + the time-log actions, all grouped on the
    // left near the info; the send time trails on the right.
    private var controlsLine: some View {
        HStack(spacing: 6) {
            Button { openInMail() } label: {
                Image(systemName: "paperplane")
                    .font(.system(size: 12)).foregroundStyle(AppTheme.person).frame(width: 18)
            }
            .buttonStyle(.plain).help("Open in Mail")
            personChip
            projectChip
            HStack(spacing: 4) {
                quickButton("1m", 1)
                quickButton("5m", 5)
                quickButton("15m", 15)
                Button { showingLogTime = true } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 12)).foregroundStyle(AppTheme.action)
                }
                .buttonStyle(.plain)
                .help("Log a custom time / edit entries")
                if loggedHours > 0 {
                    Chip(label: TimeFormat.short(hours: loggedHours), color: AppTheme.duration)
                }
            }
            Spacer(minLength: 8)
            Text(email.date.formatted(date: .omitted, time: .shortened))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // Projects are owned by the conversation; display and edit those (falling back to the message when
    // unthreaded), so filing here reaches the conversation-owned report/ledger like the diary/triage rows.
    // Person stays per-message — a sent message's recipient is specific to that message.
    private var displayedProjects: [Project] { conversation?.projects ?? email.projects }

    // Editable recipient chip → reconcile (link/create a Person) for this message.
    @ViewBuilder private var personChip: some View {
        Button { reconciling = true } label: {
            if let person = email.person {
                Chip(label: person.name, color: AppTheme.person)
            } else {
                let label = email.fromName?.isEmpty == false ? email.fromName!
                    : (email.fromAddress.isEmpty ? "Unrecognized" : email.fromAddress)
                Chip(label: label, color: AppTheme.warning)
            }
        }
        .buttonStyle(.plain)
        .help(email.person == nil
              ? "Unrecognized recipient — click to link/create a person"
              : "Recipient — click to change")
    }

    // Editable project chip → picker (set / change / remove), mirroring the triage row.
    @ViewBuilder private var projectChip: some View {
        Button { editingProject = true } label: {
            if let project = displayedProjects.first {
                Chip(label: project.name, color: AppTheme.project)
            } else {
                Chip(label: "No Project", color: AppTheme.mutedText)
            }
        }
        .buttonStyle(.plain)
        .help(displayedProjects.isEmpty ? "No project — click to choose" : "Project — click to change")
        .overlay(alignment: .bottomLeading) {
            FuzzyPickerField(
                allItems: allProjects,
                selected: Binding(
                    get: { displayedProjects },
                    set: { newValue in
                        if let convo = conversation { convo.projects = newValue } else { email.projects = newValue }
                    }),
                label: \.name,
                chipColor: AppTheme.project,
                onCreateItem: makeProject,
                isPresented: $editingProject
            )
            .frame(width: 1, height: 1)
            .opacity(0.001)
            .allowsHitTesting(false)
        }
    }

    private func makeProject(_ name: String) -> Project? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let project = Project(name: trimmed)
        modelContext.insert(project)
        return project
    }

    // Per-message reconcile: link → add the recipient address to that Person; create → new Person. The
    // recipient is specific to this sent message, so `person` is set on the message only (not the conversation).
    private func resolvePerson(_ result: AttendeeReconcileResult) {
        switch result {
        case .link(let p):
            if !email.fromAddress.isEmpty { p.emails = Person.appendingEmail(email.fromAddress, to: p.emails) }
            p.updatedAt = Date()
            email.person = p
        case .create(let name, let inst):
            let p = Person(name: name)
            if !email.fromAddress.isEmpty { p.emails = [email.fromAddress] }
            p.institution = inst
            modelContext.insert(p)
            email.person = p
        }
    }

    private func openInMail() {
        mailService.openMessage(email) { result in
            if case .failure(let error) = result { openError = error.userMessage }
        }
    }
}

private struct StandaloneMeetingRow: View {
    let minutes: Minutes
    var onTap: (() -> Void)? = nil

    @Environment(WorkspaceModel.self) private var workspace

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Color.clear.frame(width: 16, height: 1)
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.project)
                    .frame(width: 18)
                Text(minutes.summary ?? "Meeting")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    MeetingDeleteButton(minutes: minutes)
                        .frame(width: 24, alignment: .center)
                    Group {
                        if let project = minutes.projects.first {
                            Chip(label: project.name, color: AppTheme.project)
                        }
                    }
                    Chip(label: minutes.meetingAt.formatted(date: .omitted, time: .shortened),
                         color: AppTheme.project)
                    Group {
                        if let d = minutes.duration {
                            Chip(label: d.displayString, color: AppTheme.duration)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.cardRaised.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
            .onTapGesture { workspace.openInNewTab(.minutes(minutes.persistentModelID)) }
            .padding(.trailing)
        }
        .padding(.leading)
        .padding(.vertical, 1)
    }
}

private struct CompletedTaskActivityRow: View {
    let task: Task

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Color.clear.frame(width: 16, height: 1)
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.completed)
                    .frame(width: 18)
                    .padding(.leading, 2)
                Text(task.summary)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.text)
                Spacer(minLength: 0)
                if let d = task.duration {
                    Chip(label: d.displayString, color: AppTheme.duration)
                }
                if let at = task.completedAt {
                    Text(at.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedText)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.cardRaised.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .padding(.trailing)
        }
        .padding(.leading)
        .padding(.vertical, 1)
    }
}
