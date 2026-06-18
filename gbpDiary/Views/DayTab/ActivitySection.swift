import SwiftUI
import SwiftData

struct ActivitySection: View {
    @Query(sort: \FocusBlock.sortOrder) private var allFocusBlocks: [FocusBlock]
    @Environment(\.modelContext) private var modelContext

    var dayRecord: DayRecord?
    var date: Date
    var todayEntries: [TaskTimeEntry]
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
    @State private var editorDayRecord: DayRecord?

    // @Query-driven so new blocks appear immediately without relationship-refresh lag.
    private var blocks: [FocusBlock] {
        guard let id = dayRecord?.id else { return [] }
        return allFocusBlocks.filter { $0.dayRecord?.id == id }
    }

    private func meetings(for block: FocusBlock) -> [DayEntry] {
        switch block.slot {
        case .allDay:
            return meetings
        case .morning, .afternoon:
            return meetings.filter { entry in
                guard let m = entry.minutes else { return false }
                return MeetingSlotClassifier.slots(for: m, on: date).contains(block.slot)
            }
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
        if taken.contains(.allDay) { return false }
        return !taken.contains(.morning) || !taken.contains(.afternoon)
    }

    var body: some View {
        let unspecified = todayEntries.filter { $0.focusBlock == nil }.sorted { $0.date < $1.date }
        let hasContent = !blocks.isEmpty || !unspecified.isEmpty
            || !standaloneMeetings.isEmpty || !completedTasks.isEmpty

        activityHeader

        if hasContent {
            ForEach(blocks) { block in
                FocusBlockRow(block: block, date: date, meetings: meetings(for: block))
            }

            ForEach(standaloneMeetings, id: \.id) { minutes in
                StandaloneMeetingRow(minutes: minutes, onTap: { selectedMeetingMinutes = minutes })
            }

            ForEach(completedTasks) { task in
                CompletedTaskActivityRow(task: task)
            }

            if !unspecified.isEmpty {
                unspecifiedSection(unspecified)
            }

            totalFooter(
                blocks: blocks,
                unspecified: unspecified,
                meetings: standaloneMeetings,
                completedTasks: completedTasks
            )
        } else {
            Text("No activity logged for this day.")
                .foregroundStyle(.tertiary)
                .font(.callout)
                .padding(.horizontal)
                .padding(.vertical, 8)
        }

        if let record = editorDayRecord {
            Color.clear
                .sheet(isPresented: $showingAddFocusBlock, onDismiss: { editorDayRecord = nil }) {
                    FocusBlockEditorSheet(dayRecord: record)
                }
        }

        Color.clear
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
                LogTimeSheet(
                    presetFocusBlock: blocks.count == 1 ? blocks.first : nil,
                    presetDate: date,
                    availableFocusBlocks: blocks
                )
            }

        Color.clear
            .sheet(item: $selectedMeetingMinutes) { m in
                MinutesDetailView(minutes: m, asSheet: true, isNew: true)
            }
    }

    // MARK: - Activity header

    private var activityHeader: some View {
        HStack {
            Text("Activity")
                .font(AppTheme.interfaceFont(size: 12, weight: .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(AppTheme.mutedText)
            Spacer()
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

    @ViewBuilder
    private func unspecifiedSection(_ entries: [TaskTimeEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Unspecified")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 38)
                    .padding(.vertical, 4)
                Spacer()
            }
            ForEach(entries) { entry in
                UnspecifiedActivityRow(entry: entry)
            }
        }
    }

    private func totalFooter(
        blocks: [FocusBlock],
        unspecified: [TaskTimeEntry],
        meetings: [Minutes],
        completedTasks: [Task]
    ) -> some View {
        let blockHours     = blocks.reduce(0.0) { $0 + $1.duration.hoursNormalized }
        let unspecHours    = unspecified.reduce(0.0) { $0 + $1.duration.hoursNormalized }
        let meetingHours   = meetings.compactMap(\.duration).reduce(0.0) { $0 + $1.hoursNormalized }
        let taskHours      = completedTasks.compactMap(\.duration).reduce(0.0) { $0 + $1.hoursNormalized }
        let total          = blockHours + unspecHours + meetingHours + taskHours
        return HStack {
            Spacer()
            if total > 0 {
                Text("Total: \(Duration(value: total, unit: .h).displayString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.trailing)
                    .padding(.bottom, 4)
            }
        }
    }
}

private final class StandaloneTapFlags { var didTapMinutes = false }

private struct StandaloneMeetingRow: View {
    let minutes: Minutes
    var onTap: (() -> Void)? = nil

    @Environment(MinutesEditorContext.self) private var editorContext
    @Environment(\.modelContext) private var modelContext
    @State private var tapFlags = StandaloneTapFlags()
    @State private var tapCount = 0

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
                    minutesIcon
                        .frame(width: 24, alignment: .center)
                    Group {
                        if let project = minutes.projects.first {
                            Chip(label: project.name, color: AppTheme.project)
                        }
                    }
                    .frame(width: 110, alignment: .leading)
                    Chip(label: minutes.meetingAt.formatted(date: .omitted, time: .shortened),
                         color: AppTheme.project)
                        .frame(width: 76, alignment: .leading)
                    Group {
                        if let d = minutes.duration {
                            Chip(label: d.displayString, color: AppTheme.duration)
                        }
                    }
                    .frame(width: 46, alignment: .leading)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.cardRaised.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { tapCount += 1 })
            .onChange(of: tapCount) {
                if tapFlags.didTapMinutes {
                    tapFlags.didTapMinutes = false
                } else {
                    onTap?()
                }
            }
            .padding(.trailing)
        }
        .padding(.leading)
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private var minutesIcon: some View {
        if minutes.note == nil {
            Button {
                tapFlags.didTapMinutes = true
                let note = Note(content: "")
                modelContext.insert(note)
                minutes.note = note
                minutes.updatedAt = Date()
                editorContext.open(note: note, title: minutes.summary ?? "Meeting")
            } label: {
                Image(systemName: "note.text.badge.plus")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.mutedText)
            }
            .buttonStyle(.plain)
            .help("Add minutes")
        } else {
            Button {
                tapFlags.didTapMinutes = true
                if let note = minutes.note {
                    editorContext.open(note: note, title: minutes.summary ?? "Meeting")
                }
            } label: {
                Image(systemName: "note.text")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.accent)
            }
            .buttonStyle(.plain)
            .help("Open minutes")
        }
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

private final class UnspecifiedActivityTapFlags { var didTapStatus = false; var didTapFollowUp = false }

private struct UnspecifiedActivityRow: View {
    @Environment(\.modelContext) private var modelContext
    var entry: TaskTimeEntry

    @State private var showingEdit = false
    @State private var showingFollowUpPicker = false
    @State private var tapFlags = UnspecifiedActivityTapFlags()
    @State private var tapCount = 0

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Color.clear.frame(width: 16, height: 1)

            HStack(alignment: .center, spacing: 6) {
                statusIconView

                if let task = entry.task {
                    Text(task.summary)
                        .font(.subheadline)
                } else {
                    Text("Unlinked entry")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.mutedText)
                }

                if let comment = entry.comment, !comment.isEmpty {
                    Text(comment)
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    followUpIconView
                        .frame(width: 24, alignment: .center)
                    Group {
                        if let project = entry.task?.project {
                            Chip(label: project.name, color: AppTheme.project)
                        }
                    }
                    .frame(width: 110, alignment: .leading)
                    Chip(label: entry.date.formatted(date: .omitted, time: .shortened),
                         color: AppTheme.project)
                        .frame(width: 76, alignment: .leading)
                    Chip(label: entry.duration.displayString, color: AppTheme.duration)
                        .frame(width: 46, alignment: .leading)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.cardRaised.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { tapCount += 1 })
            .onChange(of: tapCount) {
                if tapFlags.didTapStatus || tapFlags.didTapFollowUp {
                    tapFlags.didTapStatus = false
                    tapFlags.didTapFollowUp = false
                } else {
                    showingEdit = true
                }
            }
            .padding(.trailing)
            .sheet(isPresented: $showingEdit) {
                LogTimeSheet(existingEntry: entry)
            }
            .contextMenu {
                if let task = entry.task {
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
                }
                Button("Delete Entry", role: .destructive) { modelContext.delete(entry) }
            }
        }
        .padding(.leading)
        .padding(.vertical, 1)
        .sheet(isPresented: $showingFollowUpPicker) {
            if let task = entry.task {
                FollowUpDateSheet(
                    initialDate: task.followUpAt ?? Calendar.current.date(byAdding: .day, value: 1, to: .now)!,
                    onSave: { date in task.setFollowUp(date: date) },
                    onRemove: task.status == .followUpPending ? { task.clearFollowUp() } : nil
                )
            }
        }
    }

    @ViewBuilder
    private var followUpIconView: some View {
        if let task = entry.task,
           task.status == .started || task.status == .followUpPending {
            Button {
                tapFlags.didTapFollowUp = true
                showingFollowUpPicker = true
            } label: {
                Image(systemName: task.status == .followUpPending ? "clock.fill" : "clock.badge")
                    .font(.system(size: 12))
                    .foregroundStyle(task.status == .followUpPending ? AppTheme.followUp : AppTheme.mutedText)
            }
            .buttonStyle(.plain)
            .help(task.status == .followUpPending ? "Edit follow-up date" : "Set follow-up date")
        }
    }

    @ViewBuilder
    private var statusIconView: some View {
        if let task = entry.task {
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
        } else {
            Image(systemName: "circle.dotted")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.mutedText)
                .frame(width: 18)
                .padding(.leading, 2)
        }
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
