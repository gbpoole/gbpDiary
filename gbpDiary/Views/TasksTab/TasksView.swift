import SwiftUI
import SwiftData

struct TasksView: View {
    @Query(sort: \Task.createdAt) private var allTasks: [Task]
    @Query(sort: \Project.name) private var allProjects: [Project]
    @Query(sort: \Person.name) private var allPeople: [Person]

    @State private var activeFilterIds: Set<String> = []
    @State private var dateRangeFilter: ClosedRange<Date>? = nil
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
        return status + projects + assignees + source
    }

    private var filteredTasks: [Task] {
        let matched = Set(FilterEngine.apply(allTasks, filters: taskFilters, activeIds: activeFilterIds).map(\.id))
        return allTasks.filter { task in
            if pendingStatusIds.contains(task.id) { return true }
            guard matched.contains(task.id) else { return false }
            guard let range = dateRangeFilter else { return true }
            let completedInRange = task.completedAt.map { range.contains($0) } ?? false
            return completedInRange || range.contains(task.createdAt)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            FilterBar(
                filters: taskFilters,
                activeFilterIds: $activeFilterIds,
                hasExtraActiveFilter: dateRangeFilter != nil,
                extraRows: AnyView(DateRangeFilterRow(range: $dateRangeFilter)),
                onClearAll: { activeFilterIds = []; dateRangeFilter = nil }
            )
            Divider()
            taskTable
        }
        .background(AppTheme.background)
        .sheet(item: $editingTask) { task in
            TaskEditorSheet(task: task, defaultDate: Date())
        }
        .onChange(of: activeFilterIds) { pendingStatusIds.removeAll() }
        .onChange(of: dateRangeFilter) { pendingStatusIds.removeAll() }
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
                Button(action: { toggleStatus(task) }) {
                    TaskStatusIcon(status: task.status)
                }
                .buttonStyle(.plain)
            }
            .width(110)
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

    private func toggleStatus(_ task: Task) {
        pendingStatusIds.insert(task.id)
        switch task.status {
        case .todo:
            task.status = .started
            task.updatedAt = Date()
        case .started:
            task.markCompleted()
        case .completed:
            task.markCancelled()
        case .followUpPending:
            task.markCancelled()
        case .cancelled:
            task.unmarkCancelled()
        }
    }
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
