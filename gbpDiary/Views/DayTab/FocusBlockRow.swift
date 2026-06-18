import SwiftUI
import SwiftData

struct FocusBlockRow: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskTimeEntry.sortOrder) private var allEntries: [TaskTimeEntry]

    var block: FocusBlock
    var date: Date
    var meetings: [DayEntry] = []

    // @Query-driven so activity rows appear immediately without relationship-refresh lag.
    private var blockActivities: [TaskTimeEntry] {
        allEntries.filter { $0.focusBlock?.id == block.id }
            .sorted { $0.date < $1.date }
    }

    // Derive locally so chips update in sync with @Query; subtract both task entries and meetings.
    private var netHours: Double {
        let taskHours = blockActivities.reduce(0.0) { $0 + $1.duration.hoursNormalized }
        let meetingHours = meetings.compactMap(\.minutes).compactMap(\.duration)
            .reduce(0.0) { $0 + $1.hoursNormalized }
        return max(0, block.duration.hoursNormalized - taskHours - meetingHours)
    }

    @State private var isCollapsed = false
    @State private var showingEditor = false
    @State private var selectedMeetingMinutes: Minutes?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            if !isCollapsed {
                VStack(alignment: .leading, spacing: 0) {
                    activityRows
                }
                .padding(.leading, 16)
            }
        }
        .sheet(item: $selectedMeetingMinutes) { m in
            MinutesDetailView(minutes: m, asSheet: true)
        }
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 6) {
            chevronButton

            HStack(alignment: .center, spacing: 6) {
                sourceIcon
                Text(block.displayLabel)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer(minLength: 0)
                durationChips
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onTapGesture { showingEditor = true }
            .padding(.trailing)
            .contextMenu {
                Button("Edit Focus Block…") { showingEditor = true }
            }
            .sheet(isPresented: $showingEditor) {
                if let record = block.dayRecord {
                    FocusBlockEditorSheet(dayRecord: record, existingBlock: block)
                }
            }
        }
        .padding(.leading)
        .padding(.vertical, 2)
    }

    private var chevronButton: some View {
        Button {
            isCollapsed.toggle()
        } label: {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedText)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .frame(width: 16, height: 22)
    }

    private var sourceIcon: some View {
        Image(systemName: "scope")
            .foregroundStyle(AppTheme.tag)
            .font(.system(size: 14))
            .frame(width: 18, height: 18)
    }

    private var durationChips: some View {
        HStack(spacing: 4) {
            Chip(label: block.slot.displayName, color: AppTheme.project)
            if netHours > 0 && (!blockActivities.isEmpty || !meetings.isEmpty) {
                let netDur = Duration(value: netHours, unit: .h)
                Chip(label: netDur.displayString, color: AppTheme.duration)
            }
        }
    }

    @ViewBuilder
    private var meetingRows: some View {
        ForEach(meetings, id: \.id) { entry in
            if let minutes = entry.minutes {
                MeetingActivityRow(minutes: minutes, onTap: { selectedMeetingMinutes = minutes })
            }
        }
    }

    @ViewBuilder
    private var activityRows: some View {
        meetingRows
        ForEach(blockActivities) { entry in
            ActivityEntryRow(entry: entry)
        }
    }
}

private final class MeetingActivityTapFlags { var didTapMinutes = false }

private struct MeetingActivityRow: View {
    var minutes: Minutes
    var onTap: (() -> Void)? = nil

    @Environment(MinutesEditorContext.self) private var editorContext
    @Environment(\.modelContext) private var modelContext
    @State private var tapFlags = MeetingActivityTapFlags()
    @State private var tapCount = 0

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Color.clear.frame(width: 16, height: 1)
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.project)
                    .frame(width: 18)
                Text(minutes.summary ?? "Meeting")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.text)
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

private final class ActivityEntryTapFlags { var didTapStatus = false; var didTapFollowUp = false; var didTapAddTime = false; var didTapEditTask = false }

private struct ActivityEntryRow: View {
    var entry: TaskTimeEntry

    @Environment(\.modelContext) private var modelContext
    @State private var showingEdit = false
    @State private var showingFollowUpPicker = false
    @State private var showingAddTime = false
    @State private var editingTask: Task?
    @State private var tapFlags = ActivityEntryTapFlags()
    @State private var tapCount = 0

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Color.clear.frame(width: 16, height: 1)
                .sheet(isPresented: $showingAddTime) {
                    LogTimeSheet(presetTask: entry.task, presetFocusBlock: entry.focusBlock, presetDate: entry.date)
                }
                .overlay {
                    Color.clear.sheet(item: $editingTask) { task in
                        TaskEditorSheet(task: task, defaultDate: entry.date)
                    }
                }

            HStack(alignment: .center, spacing: 6) {
                statusIconView

                if let task = entry.task {
                    Text(task.summary)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.text)
                } else {
                    Text("Unlinked activity")
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
                    editTaskIconView
                        .frame(width: 24, alignment: .center)
                    addTimeIconView
                        .frame(width: 24, alignment: .center)
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
                if tapFlags.didTapStatus || tapFlags.didTapFollowUp || tapFlags.didTapAddTime || tapFlags.didTapEditTask {
                    tapFlags.didTapStatus = false
                    tapFlags.didTapFollowUp = false
                    tapFlags.didTapAddTime = false
                    tapFlags.didTapEditTask = false
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
                    Button("Edit Task…") { editingTask = task }
                    Divider()
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
        .onChange(of: showingAddTime) { _, isShowing in
            if !isShowing, let task = entry.task,
               task.status == .todo, !task.timeEntries.isEmpty {
                task.status = .started
                task.updatedAt = Date()
            }
        }
    }

    @ViewBuilder
    private var editTaskIconView: some View {
        if let task = entry.task {
            Button {
                tapFlags.didTapEditTask = true
                editingTask = task
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.mutedText)
            }
            .buttonStyle(.plain)
            .help("Edit task")
        }
    }

    @ViewBuilder
    private var addTimeIconView: some View {
        if let task = entry.task,
           task.status == .todo || task.status == .started {
            Button {
                tapFlags.didTapAddTime = true
                showingAddTime = true
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.mutedText)
            }
            .buttonStyle(.plain)
            .help("Log time")
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
            Image(systemName: "circle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 18)
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
