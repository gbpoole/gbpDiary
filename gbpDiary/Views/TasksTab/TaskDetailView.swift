import SwiftUI
import SwiftData

// The `.task(...)` workspace tab — a page-styled detail view for one Task (opened by double-clicking a row
// in TasksView, like Projects/People). Its focus is the **Time Log**: every TaskTimeEntry logged against the
// task, each clickable to jump to the diary day where it lives (WorkspaceModel.revealTimeEntry). Full
// metadata editing stays in the proven TaskEditorSheet (a task has far more fields than Project/Person).
struct TaskDetailView: View {
    @Bindable var task: Task
    var asSheet: Bool = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(WorkspaceModel.self) private var workspace

    // Whole-store queries feed the canonical ledger so a focus block's NET (capacity − other in-block
    // activity) is accurate — the same figure as the Tasks Time column and the Timesheet.
    @Query(sort: \Task.createdAt) private var allTasks: [Task]
    @Query private var allFocusBlocks: [FocusBlock]
    @Query private var allConversations: [EmailConversation]
    @Query private var allMeetings: [Minutes]

    @State private var editingTask: Task?
    @State private var showingAddTime = false

    // One log with both time entries and the focus blocks this task backs, newest first.
    private enum LogItem: Identifiable {
        case entry(TaskTimeEntry)
        case block(FocusBlock)
        var id: UUID { switch self { case .entry(let e): e.id; case .block(let b): b.id } }
        var date: Date {
            switch self {
            case .entry(let e): e.date
            case .block(let b): b.dayRecord?.date ?? .distantPast
            }
        }
    }
    private var logItems: [LogItem] {
        (task.timeEntries.map(LogItem.entry) + task.focusBlocks.map(LogItem.block))
            .sorted { $0.date > $1.date }
    }

    private var blockNet: [UUID: Double] {
        TimeLedgerProjection.blockNet(focusBlocks: allFocusBlocks, tasks: allTasks,
                                      conversations: allConversations, meetings: allMeetings)
    }
    private func netHours(for block: FocusBlock) -> Double { blockNet[block.id] ?? 0 }

    private var totalHours: Double {
        TaskTimeReport.totalHours(entryHours: task.loggedHoursNormalized,
                                  hasEntries: !task.timeEntries.isEmpty,
                                  legacyHours: task.duration?.hoursNormalized,
                                  blockNets: task.focusBlocks.map(netHours(for:)))
    }

    var body: some View {
        if asSheet {
            NavigationStack { coreContent }
            #if os(macOS)
            .frame(minWidth: 480, minHeight: 480)
            #endif
        } else {
            coreContent
        }
    }

    private var coreContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 4)
            DayActionBar(items: actionItems)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    section("Time Log (\(logItems.count))") { timeLogContent }
                    if !task.children.isEmpty {
                        section("Subtasks (\(task.children.count))") { subtasksContent }
                    }
                }
                .padding(.bottom, 28)
            }
        }
        .background(AppTheme.background)
        .navigationTitle(task.summary)
        .toolbar {
            if asSheet {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .sheet(item: $editingTask) { t in TaskEditorSheet(task: t, defaultDate: Date()) }
        .sheet(isPresented: $showingAddTime) { LogTimeSheet(presetTask: task, presetDate: Date()) }
    }

    private var actionItems: [DayActionItem] {
        [
            DayActionItem(id: "edit", systemName: "pencil", color: AppTheme.project,
                          tooltip: "Edit task") { editingTask = task },
            DayActionItem(id: "addTime", systemName: "clock.badge.plus", color: AppTheme.duration,
                          tooltip: "Add time entry") { showingAddTime = true },
        ]
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(task.summary)
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.text)
            metadataRow
            if let notes = task.notes, !notes.isEmpty {
                Text(notes)
                    .font(.callout)
                    .foregroundStyle(AppTheme.mutedText)
                    .lineLimit(4)
            }
        }
    }

    private var metadataRow: some View {
        FlowLayout(spacing: 6) {
            TaskStatusMenu(task: task) { statusLabel }
            if let project = task.project { Chip(label: project.name, color: AppTheme.project) }
            if let assignee = task.assignee { Chip(label: assignee.name, color: AppTheme.person) }
            if task.priority != .none { Chip(label: "Pri \(task.priority.short)", color: AppTheme.followUp) }
            if let due = task.dueAt {
                Chip(label: "Due \(due.formatted(.dateTime.day().month(.abbreviated)))", color: AppTheme.followUp)
            }
            if let sched = task.scheduledAt {
                Chip(label: "Sched \(sched.formatted(.dateTime.day().month(.abbreviated)))", color: AppTheme.today)
            }
            if totalHours > 0 {
                Chip(label: "Logged \(TimeFormat.hours(totalHours))", color: AppTheme.duration)
            }
        }
    }

    private var statusLabel: some View {
        let (icon, color, text): (String, Color, String) = {
            switch task.status {
            case .todo:            ("circle", AppTheme.mutedText, "To do")
            case .started:         ("play.circle.fill", AppTheme.today, "Started")
            case .completed:       ("checkmark.circle.fill", AppTheme.completed, "Completed")
            case .cancelled:       ("xmark.circle.fill", AppTheme.mutedText, "Cancelled")
            case .followUpPending: ("clock.fill", AppTheme.followUp, "Follow up")
            }
        }()
        return HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(color)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(AppTheme.chipBackground(color), in: Capsule())
    }

    // MARK: - Sections

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        DaySectionHeader(title: title)
        VStack(alignment: .leading, spacing: 4) { content() }
            .padding(.horizontal)
    }

    @ViewBuilder private var timeLogContent: some View {
        if logItems.isEmpty {
            Text("No time logged against this task.")
                .foregroundStyle(AppTheme.mutedText).font(.callout).padding(.vertical, 2)
        } else {
            ForEach(logItems) { item in
                switch item {
                case .entry(let entry): logRow(entry: entry)
                case .block(let block): logRow(block: block)
                }
            }
        }
    }

    // A logged time entry → jumps to the diary day where it sits inside its block.
    private func logRow(entry: TaskTimeEntry) -> some View {
        logRow(icon: "clock", date: entry.date, hours: entry.duration.displayString,
               detail: entry.comment) { workspace.revealTimeEntry(entry) }
    }

    // A focus block backing this task → shows its dynamic NET hours; jumps to the block in the diary.
    private func logRow(block: FocusBlock) -> some View {
        let detail = [block.slot.displayName, block.comment].compactMap { $0 }
            .filter { !$0.isEmpty }.joined(separator: " · ")
        return logRow(icon: "square.stack", date: block.dayRecord?.date ?? block.createdAt,
                      hours: Duration(value: netHours(for: block), unit: .h).displayString,
                      detail: detail.isEmpty ? nil : detail) { workspace.revealFocusBlock(block) }
    }

    private func logRow(icon: String, date: Date, hours: String, detail: String?,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(AppTheme.duration).font(.system(size: 12))
                    .frame(width: 18).padding(.top, 2)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()))
                            .foregroundStyle(AppTheme.text)
                        Chip(label: hours, color: AppTheme.duration)
                    }
                    if let detail, !detail.isEmpty {
                        Text(detail).font(.caption).foregroundStyle(AppTheme.mutedText).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right.circle")
                    .foregroundStyle(AppTheme.mutedText).font(.system(size: 12)).padding(.top, 2)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Go to this in the diary")
    }

    @ViewBuilder private var subtasksContent: some View {
        ForEach(task.children) { child in TaskRowView(task: child, onEdit: { editingTask = child }) }
    }
}
