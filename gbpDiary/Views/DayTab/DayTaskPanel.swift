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

    @State private var newTaskText = ""
    @State private var editingTask: Task?
    @State private var collapsed: Set<String> = []

    private var buckets: DayTaskBuckets.Buckets {
        DayTaskBuckets.partition(allTasks: allTasks, date: date)
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
            Image(systemName: "plus.circle.fill").foregroundStyle(AppTheme.accent)
            TextField("Quick add task…", text: $newTaskText)
                .textFieldStyle(.plain)
                .onSubmit { addTask() }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(AppTheme.cardRaised.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
        .padding(.horizontal).padding(.bottom, 4)
    }

    private func addTask() {
        let trimmed = newTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        modelContext.insert(Task(summary: trimmed))   // needsTriage == true → lands in the Inbox
        newTaskText = ""
    }

    // Action buckets (triaged tasks) — simple actionable rows.
    @ViewBuilder
    private func bucketSection(_ title: String, key: String, tasks: [Task], tint: Color) -> some View {
        if !tasks.isEmpty {
            sectionHeader(title, key: key, count: tasks.count, tint: tint)
            if !collapsed.contains(key) {
                ForEach(sortedForDisplay(tasks, key: key)) { task in
                    TaskRowView(task: task, onEdit: { editingTask = task })
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
