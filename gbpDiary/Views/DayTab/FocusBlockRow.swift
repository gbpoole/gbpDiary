import SwiftUI
import SwiftData

struct FocusBlockRow: View {
    @Environment(\.modelContext) private var modelContext

    var block: FocusBlock
    var date: Date
    // Entries whose time falls in this block's range (derived by ActivitySection, not stored).
    var entries: [TaskTimeEntry] = []
    var meetings: [DayEntry] = []
    var emails: [EmailMessage] = []   // sent + received in this block (received carry no logged time)

    private var blockActivities: [TaskTimeEntry] {
        entries.sorted { $0.date < $1.date }
    }

    private var netHours: Double {
        let taskHours = entries.reduce(0.0) { $0 + $1.duration.hoursNormalized }
        let meetingHours = meetings.compactMap(\.minutes).compactMap(\.duration)
            .reduce(0.0) { $0 + $1.hoursNormalized }
        // Only sent emails carry logged time; received contribute 0, so summing all is correct.
        let emailHours = emails.flatMap(\.timeEntries).reduce(0.0) { $0 + $1.duration.hoursNormalized }
        return FocusBlockMath.netHours(capacity: block.duration.hoursNormalized,
                                       loggedHours: taskHours + meetingHours + emailHours)
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
            MinutesDetailView(minutes: m, asSheet: true).presentationSizing(.fitted)
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
                if let comment = block.comment, !comment.isEmpty {
                    Text(comment)
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedText)
                        .lineLimit(1)
                }
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
                Divider()
                Button("Delete Focus Block", role: .destructive) { modelContext.delete(block) }
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
            if netHours > 0 && (!blockActivities.isEmpty || !meetings.isEmpty || !emails.isEmpty) {
                let netDur = Duration(value: netHours, unit: .h)
                Chip(label: netDur.displayString, color: AppTheme.duration)
            }
        }
    }

    // A block's meetings and time entries interleaved in chronological order. (Sent emails are
    // collected into one collapsible group rendered after these — see activityRows.)
    private enum BlockItem: Identifiable {
        case meeting(DayEntry)
        case entry(TaskTimeEntry)
        var id: String {
            switch self {
            case .meeting(let e): "m-\(e.id.uuidString)"
            case .entry(let e):   "e-\(e.id.uuidString)"
            }
        }
    }

    private var orderedBlockItems: [BlockItem] {
        var items: [(Date, BlockItem)] = []
        for meeting in meetings { items.append((meeting.minutes?.meetingAt ?? .distantPast, .meeting(meeting))) }
        for entry in entries { items.append((entry.date, .entry(entry))) }
        return items.sorted { $0.0 < $1.0 }.map(\.1)
    }

    @ViewBuilder
    private var activityRows: some View {
        ForEach(orderedBlockItems) { item in
            switch item {
            case .meeting(let entry):
                if let minutes = entry.minutes { MeetingActivityRow(minutes: minutes) }
            case .entry(let entry):
                ActivityEntryRow(entry: entry)
            }
        }
        if !emails.isEmpty {
            EmailDigestGroupRow(emails: emails)
        }
    }
}

private struct MeetingActivityRow: View {
    var minutes: Minutes

    @Environment(WorkspaceModel.self) private var workspace

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

private final class ActivityEntryTapFlags { var didTapStatus = false; var didTapFollowUp = false; var didTapAddTime = false; var didTapEditTask = false }

// Internal (not private) so the Activity section can render standalone, out-of-range entries too.
struct ActivityEntryRow: View {
    var entry: TaskTimeEntry

    @Environment(\.modelContext) private var modelContext
    @State private var showingEdit = false
    @State private var showingAddTime = false
    @State private var editingTask: Task?
    @State private var tapFlags = ActivityEntryTapFlags()
    @State private var tapCount = 0

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Color.clear.frame(width: 16, height: 1)
                .sheet(isPresented: $showingAddTime) {
                    LogTimeSheet(presetTask: entry.task, presetDate: entry.date)
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
                    Group {
                        if let project = entry.task?.project {
                            Chip(label: project.name, color: AppTheme.project)
                        }
                    }
                    Chip(label: entry.date.formatted(date: .omitted, time: .shortened),
                         color: AppTheme.project)
                    Chip(label: entry.duration.displayString, color: AppTheme.duration)
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
                    .foregroundStyle(AppTheme.action)
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
                    .foregroundStyle(AppTheme.action)
            }
            .buttonStyle(.plain)
            .help("Log time")
        }
    }


    @ViewBuilder
    private var statusIconView: some View {
        if let task = entry.task {
            TaskStatusMenu(task: task, onBeforeChange: { tapFlags.didTapStatus = true }) {
                Image(systemName: taskStatusIcon(task))
                    .font(.system(size: 12))
                    .foregroundStyle(taskStatusColor(task))
                    .frame(width: 18)
            }
            // Opening the menu counts as a status tap, so the row's tap-to-edit is suppressed.
            .simultaneousGesture(TapGesture().onEnded { tapFlags.didTapStatus = true })
        } else {
            Image(systemName: "circle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 18)
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
