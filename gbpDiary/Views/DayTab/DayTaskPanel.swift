import SwiftUI
import SwiftData

// The diary's always-visible right-hand task panel: a quick-add capture field plus the day's actionable
// buckets — Overdue / Due today / In-progress / Scheduled / Inbox. Action buckets use `TaskRowView`
// (status/log-time/edit); the Inbox uses the inline `TaskTriageRow`. Everything is `@Query`-backed, so
// edits reflect live in the diary (complete → Completed; log time → Activity; Reviewed → leaves Inbox).
struct DayTaskPanel: View {
    let date: Date

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Task.createdAt) private var allTasks: [Task]
    @Query private var allPeople: [Person]

    @State private var newTaskText = ""
    @State private var editingTask: Task?
    @State private var collapsed: Set<String> = []

    // The configured "Me" person; the panel is scoped to tasks assigned to them.
    private var mePerson: Person? {
        AppSettingsStore.myPersonID.flatMap { id in allPeople.first { $0.id == id } }
    }

    private var buckets: DayTaskBuckets.Buckets {
        // Only tasks assigned to Me (when configured); otherwise fall back to all tasks.
        let mine = mePerson.map { me in allTasks.filter { $0.assignee?.id == me.id } } ?? allTasks
        return DayTaskBuckets.partition(allTasks: mine, date: date)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    quickAdd
                    bucketSection("Overdue", key: "overdue", tasks: buckets.overdue, tint: AppTheme.destructive)
                    bucketSection("Due Today", key: "due", tasks: buckets.dueToday, tint: AppTheme.followUp)
                    bucketSection("In Progress", key: "started", tasks: buckets.inProgress, tint: AppTheme.started)
                    bucketSection("Scheduled", key: "scheduled", tasks: buckets.scheduled, tint: AppTheme.accent)
                    bucketSection("To Do", key: "todo", tasks: buckets.todo, tint: AppTheme.mutedText)
                    inboxSection
                }
                .padding(.vertical, 6)
            }
        }
        .background(AppTheme.background)
        .sheet(item: $editingTask) { task in TaskEditorSheet(task: task, defaultDate: date) }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.square").foregroundStyle(AppTheme.mutedText).font(.system(size: 12))
            Text("TASKS")
                .font(AppTheme.interfaceFont(size: 12, weight: .semibold))
                .tracking(0.8).foregroundStyle(AppTheme.mutedText)
            Spacer()
        }
        .padding(.horizontal).padding(.top, 12).padding(.bottom, 8)
    }

    private var quickAdd: some View {
        HStack(spacing: 6) {
            Button { addTask() } label: {
                Image(systemName: "plus.circle.fill").font(.callout).foregroundStyle(AppTheme.accent)
            }
            .buttonStyle(.plain)
            .help("Add task")
            TextField("Add a task…", text: $newTaskText)
                .textFieldStyle(.plain)
                .font(.callout)
                .onSubmit { addTask() }
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Color.secondary.opacity(0.12), in: Capsule())
        .padding(.horizontal).padding(.top, 4).padding(.bottom, 6)
    }

    private func addTask() {
        let trimmed = newTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let task = Task(summary: trimmed)   // needsTriage == true → lands in the Inbox
        task.assignee = mePerson            // assign to Me so captures appear in this (Me-scoped) panel
        modelContext.insert(task)
        newTaskText = ""
    }

    // Action buckets (triaged tasks) — compact two-line rows.
    @ViewBuilder
    private func bucketSection(_ title: String, key: String, tasks: [Task], tint: Color) -> some View {
        if !tasks.isEmpty {
            sectionHeader(title, key: key, count: tasks.count, tint: tint)
            if !collapsed.contains(key) {
                ForEach(sortedForDisplay(tasks, key: key)) { task in
                    DayTaskPanelRow(task: task, onEdit: { editingTask = task })
                }
            }
        }
    }

    // Inbox (untriaged) — always shown (even empty) so quick-add feedback is visible; inline triage rows.
    @ViewBuilder private var inboxSection: some View {
        sectionHeader("Inbox", key: "inbox", count: buckets.inbox.count, tint: AppTheme.warning)
        if !collapsed.contains("inbox") {
            if buckets.inbox.isEmpty {
                Text("Inbox clear.")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.horizontal).padding(.vertical, 6)
            } else {
                ForEach(buckets.inbox) { task in
                    TaskTriageRow(task: task, onEdit: { editingTask = task })
                }
            }
        }
    }

    private func sectionHeader(_ title: String, key: String, count: Int, tint: Color) -> some View {
        Button { toggle(key) } label: {
            HStack(spacing: 6) {
                Image(systemName: collapsed.contains(key) ? "chevron.right" : "chevron.down")
                    .font(.caption2).foregroundStyle(.tertiary)
                Text(title).font(.subheadline.bold()).foregroundStyle(tint)
                Text("\(count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal).padding(.top, 12).padding(.bottom, 4)
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ key: String) {
        if collapsed.contains(key) { collapsed.remove(key) } else { collapsed.insert(key) }
    }

    private func sortedForDisplay(_ tasks: [Task], key: String) -> [Task] {
        switch key {
        case "overdue", "due":
            return tasks.sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
        case "scheduled":
            return tasks.sorted { ($0.scheduledAt ?? .distantFuture) < ($1.scheduledAt ?? .distantFuture) }
        case "todo":
            // The catch-all is unordered by date — rank it by urgency (same score as the Tasks table).
            return tasks.sorted { TaskUrgency.score(for: $0) > TaskUrgency.score(for: $1) }
        default:
            return tasks
        }
    }
}

// A compact two-line task row for the diary panel (email-list style): status icon + metadata chips
// (project / assignee / priority / dates / flags) on the first line, the summary on the second.
// No inline edit button — double-click opens the editor; status/log-time/delete live in the context menu.
private struct DayTaskPanelRow: View {
    @Bindable var task: Task
    var onEdit: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var showingLogTime = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Line 1: the status icon lines up with the metadata chips.
            HStack(alignment: .center, spacing: 8) {
                TaskStatusMenu(task: task) {
                    Image(systemName: statusIcon)
                        .foregroundStyle(statusColor).font(.system(size: 15)).frame(width: 20)
                }
                metaLine
                Spacer(minLength: 0)
            }
            // Line 2: summary, indented to align under the chips.
            Text(task.summary)
                .font(AppTheme.bodyFont(size: 13))
                .foregroundStyle(task.status == .cancelled ? AppTheme.mutedText : AppTheme.text)
                .strikethrough(task.status == .cancelled)
                .lineLimit(2)
                .padding(.leading, 28)
        }
        .padding(.horizontal).padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onEdit() }
        .contextMenu {
            Button("Edit…", action: onEdit)
            Button("Log time today…") { showingLogTime = true }
            Divider()
            Button("Delete", role: .destructive) { modelContext.delete(task) }
        }
        .sheet(isPresented: $showingLogTime) {
            LogTimeSheet(presetTask: task, presetDate: Date())
        }
    }

    // First line: small flag glyphs then the metadata chips (wrap when the panel is narrow).
    private var metaLine: some View {
        // Centred so the small flag/mail glyphs line up with the taller chips. Assignee is omitted —
        // every task in this panel is assigned to Me by construction.
        FlowLayout(spacing: 4, centerVertically: true) {
            if task.isBlocked { glyph("lock.fill", AppTheme.destructive, "Blocked by an unfinished task") }
            if task.recurrenceRule != nil { glyph("arrow.clockwise", .secondary, "Repeats") }
            if let project = task.project { Chip(label: project.name, color: AppTheme.project) }
            if task.priority != .none { Chip(label: task.priority.short, color: priorityChipColor) }
            if let due = task.dueAt {
                Chip(label: "⚑ \(due.formatted(.dateTime.day().month()))",
                     color: task.isOverdue ? AppTheme.destructive : AppTheme.followUp)
            }
            if let scheduled = task.scheduledAt {
                Chip(label: "◷ \(scheduled.formatted(.dateTime.day().month()))", color: AppTheme.accent)
            }
            if let dur = task.loggedDuration {
                Chip(label: dur.displayString, color: AppTheme.duration)
            }
            if task.originEmail != nil { glyph("envelope", .secondary, "From an email") }
        }
    }

    private func glyph(_ system: String, _ color: Color, _ help: String) -> some View {
        Image(systemName: system).font(.caption2).foregroundStyle(color).help(help)
    }

    private var priorityChipColor: Color {
        switch task.priority {
        case .high:   AppTheme.destructive
        case .medium: AppTheme.followUp
        default:      AppTheme.mutedText
        }
    }

    private var statusIcon: String {
        switch task.status {
        case .todo:            "circle"
        case .started:         "play.circle.fill"
        case .completed:       "checkmark.circle.fill"
        case .cancelled:       "xmark.circle.fill"
        case .followUpPending: "arrow.clockwise.circle.fill"
        }
    }
    private var statusColor: Color {
        switch task.status {
        case .todo:            AppTheme.mutedText
        case .started:         AppTheme.started
        case .completed:       AppTheme.completed
        case .cancelled:       AppTheme.mutedText
        case .followUpPending: AppTheme.followUp
        }
    }
}
