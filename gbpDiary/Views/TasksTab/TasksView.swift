import SwiftUI
import SwiftData

struct TasksView: View {
    @Query(sort: \Task.createdAt) private var allTasks: [Task]
    @Query(sort: \Project.name) private var allProjects: [Project]

    @State private var statusFilter: TaskStatus? = nil
    @State private var projectFilter: Project? = nil
    @State private var personFilter: Person? = nil
    @State private var dateRangeFilter: ClosedRange<Date>? = nil
    @State private var editingTask: Task? = nil
    @State private var pendingStatusIds: Set<UUID> = []

    private var filteredTasks: [Task] {
        allTasks.filter { task in
            if pendingStatusIds.contains(task.id) { return true }
            let statusOk = statusFilter.map { task.status == $0 } ?? true
            let projectOk = projectFilter.map { task.project?.id == $0.id } ?? true
            let personOk = personFilter.map { task.assignee?.id == $0.id } ?? true
            let dateOk: Bool
            if let range = dateRangeFilter {
                let completedInRange = task.completedAt.map { range.contains($0) } ?? false
                let createdInRange = range.contains(task.createdAt)
                dateOk = completedInRange || createdInRange
            } else {
                dateOk = true
            }
            return statusOk && projectOk && personOk && dateOk
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TasksFilterBar(
                statusFilter: $statusFilter,
                projectFilter: $projectFilter,
                personFilter: $personFilter,
                dateRangeFilter: $dateRangeFilter
            )
            Divider()
            taskTable
        }
        .background(AppTheme.background)
        .sheet(item: $editingTask) { task in
            TaskEditorSheet(task: task, defaultDate: Date())
        }
        .onChange(of: statusFilter) { pendingStatusIds.removeAll() }
        .onChange(of: projectFilter) { pendingStatusIds.removeAll() }
        .onChange(of: personFilter) { pendingStatusIds.removeAll() }
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
