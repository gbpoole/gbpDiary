import SwiftUI
import SwiftData

struct TasksView: View {
    @Query(sort: \Task.createdAt) private var allTasks: [Task]
    @Query(sort: \Project.name) private var allProjects: [Project]
    @Query(sort: \Person.name) private var allPeople: [Person]

    // Filter state is held on the active workspace tab so it survives navigation and differs per tab.
    @Environment(WorkspaceModel.self) private var workspace
    private var filterState: TasksFilterState { workspace.active.tasksFilter }
    @State private var editingTask: Task? = nil
    @State private var pendingStatusIds: Set<UUID> = []

    private var taskFilters: [PickerFilter<Task>] {
        let status = TaskStatus.allCases.map { s in
            PickerFilter<Task>(id: "status.\(s)", label: s.displayName, chipColor: AppTheme.accent, group: "Status") { $0.status == s }
        }
        let projects = allProjects.map { p in
            PickerFilter<Task>(id: "project.\(p.id)", label: p.name, chipColor: AppTheme.project, group: "Project") { $0.project?.id == p.id }
        }
        let assignees = allPeople.map { p in
            PickerFilter<Task>(id: "assignee.\(p.id)", label: p.name, chipColor: AppTheme.person, group: "Assignee") { $0.assignee?.id == p.id }
        }
        let source = [
            PickerFilter<Task>(id: "source.email", label: "From email", chipColor: AppTheme.person, group: "Source") { $0.originEmail != nil }
        ]
        let priorities = TaskPriority.allCases.filter { $0 != .none }.map { p in
            PickerFilter<Task>(id: "priority.\(p.rawValue)", label: p.displayName, chipColor: priorityColor(p), group: "Priority") { $0.priority == p }
        }
        let flags = [
            PickerFilter<Task>(id: "flag.overdue", label: "Overdue", chipColor: AppTheme.destructive, group: "Flags") { $0.isOverdue },
            PickerFilter<Task>(id: "flag.dueToday", label: "Due today", chipColor: AppTheme.followUp, group: "Flags") { $0.isDueToday },
            PickerFilter<Task>(id: "flag.hasDue", label: "Has due", chipColor: AppTheme.mutedText, group: "Flags") { $0.dueAt != nil }
        ]
        return status + priorities + flags + projects + assignees + source
    }

    private func priorityColor(_ p: TaskPriority) -> Color {
        switch p {
        case .high:   AppTheme.destructive
        case .medium: AppTheme.followUp
        case .low:    AppTheme.mutedText
        case .none:   AppTheme.mutedText
        }
    }

    private var filteredTasks: [Task] {
        let matched = Set(FilterEngine.apply(allTasks, filters: taskFilters, activeIds: filterState.activeFilterIds).map(\.id))
        let base = allTasks.filter { task in
            if pendingStatusIds.contains(task.id) { return true }
            guard matched.contains(task.id) else { return false }
            guard let range = filterState.dateRange else { return true }
            let completedInRange = task.completedAt.map { range.contains($0) } ?? false
            return completedInRange || range.contains(task.createdAt)
        }
        return sorted(base)
    }

    private func sorted(_ tasks: [Task]) -> [Task] {
        switch filterState.sortMode {
        case .urgency:
            return tasks
                .map { ($0, TaskUrgency.score(for: $0)) }
                .sorted { $0.1 > $1.1 }
                .map(\.0)
        case .created:
            return tasks.sorted { $0.createdAt > $1.createdAt }
        case .due:
            return tasks.sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
        }
    }

    var body: some View {
        @Bindable var filter = filterState
        return VStack(spacing: 0) {
            FilterBar(
                filters: taskFilters,
                activeFilterIds: $filter.activeFilterIds,
                hasExtraActiveFilter: filter.dateRange != nil,
                extraRows: AnyView(DateRangeFilterRow(range: $filter.dateRange)),
                onClearAll: { filter.activeFilterIds = []; filter.dateRange = nil }
            )
            HStack(spacing: 6) {
                Spacer()
                Text("Sort").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $filter.sortMode) {
                    ForEach(TaskSortMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden().fixedSize()
            }
            .padding(.horizontal).padding(.bottom, 4)
            Divider()
            taskTable
        }
        .background(AppTheme.background)
        .sheet(item: $editingTask) { task in
            TaskEditorSheet(task: task, defaultDate: Date())
        }
        .onChange(of: filterState.activeFilterIds) { pendingStatusIds.removeAll() }
        .onChange(of: filterState.dateRange) { pendingStatusIds.removeAll() }
    }

    #if os(macOS)
    private var taskTable: some View {
        Table(filteredTasks) {
            TableColumn("Summary") { task in
                Text(task.summary)
                    .lineLimit(1)
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundStyle(pendingStatusIds.contains(task.id) ? AppTheme.mutedText : AppTheme.text)
                    .onTapGesture { editingTask = task }
            }
            TableColumn("Status") { task in
                TaskStatusMenu(task: task, onBeforeChange: { pendingStatusIds.insert(task.id) }) {
                    TaskStatusIcon(status: task.status)
                }
            }
            .width(130)
            TableColumn("Urg") { task in
                Text(String(format: "%.1f", TaskUrgency.score(for: task)))
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundStyle(AppTheme.mutedText)
                    .monospacedDigit()
            }
            .width(46)
            TableColumn("Pri") { task in
                if task.priority != .none {
                    Chip(label: task.priority.short, color: priorityColor(task.priority))
                }
            }
            .width(44)
            TableColumn("Due") { task in
                if let due = task.dueAt {
                    Text(due, format: .dateTime.month(.abbreviated).day())
                        .foregroundStyle(task.isOverdue ? AppTheme.destructive : AppTheme.mutedText)
                }
            }
            .width(80)
            TableColumn("Project") { task in
                Text(task.project?.name ?? "")
                    .foregroundStyle(AppTheme.project)
                    .lineLimit(1)
            }
            TableColumn("Assignee") { task in
                Text(task.assignee?.name ?? "")
                    .foregroundStyle(AppTheme.person)
                    .lineLimit(1)
            }
            TableColumn("Scheduled") { task in
                if let s = task.scheduledAt {
                    Text(s, format: .dateTime.month(.abbreviated).day().year())
                        .foregroundStyle(AppTheme.mutedText)
                }
            }
            .width(100)
            TableColumn("Created") { task in
                Text(task.createdAt, format: .dateTime.month(.abbreviated).day().year())
                    .foregroundStyle(AppTheme.mutedText)
            }
            .width(100)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .animation(.easeInOut(duration: 0.25), value: filteredTasks.map(\.id))
    }
    #else
    private var taskTable: some View {
        List(filteredTasks) { task in
            TaskRowView(task: task, onEdit: { editingTask = task })
        }
    }
    #endif

}

struct TaskStatusIcon: View {
    let status: TaskStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .font(.system(size: 13))
            Text(statusLabel)
                .font(.caption)
                .foregroundStyle(AppTheme.mutedText)
        }
    }

    private var iconName: String {
        switch status {
        case .todo:            return "circle"
        case .started:         return "circle.lefthalf.filled"
        case .completed:       return "checkmark.circle.fill"
        case .cancelled:       return "xmark.circle"
        case .followUpPending: return "clock.arrow.circlepath"
        }
    }

    private var iconColor: Color {
        switch status {
        case .todo:            return AppTheme.mutedText
        case .started:         return AppTheme.started
        case .completed:       return AppTheme.completed
        case .cancelled:       return AppTheme.mutedText
        case .followUpPending: return AppTheme.followUp
        }
    }

    private var statusLabel: String {
        switch status {
        case .todo:            return "To Do"
        case .started:         return "Started"
        case .completed:       return "Done"
        case .cancelled:       return "Cancelled"
        case .followUpPending: return "Follow-up"
        }
    }
}
