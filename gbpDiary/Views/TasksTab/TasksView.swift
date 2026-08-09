import SwiftUI
import SwiftData

struct TasksView: View {
    @Query(sort: \Task.createdAt) private var allTasks: [Task]
    @Query(sort: \Project.name) private var allProjects: [Project]
    @Query(sort: \Person.name) private var allPeople: [Person]

    @Environment(\.modelContext) private var modelContext
    // Filter state is held on the active workspace tab so it survives navigation and differs per tab.
    @Environment(WorkspaceModel.self) private var workspace
    private var filterState: TasksFilterState { workspace.active.tasksFilter }
    @State private var editingTask: Task? = nil
    @State private var pendingStatusIds: Set<UUID> = []
    @State private var selection: Set<UUID> = []
    @State private var confirmingBulkDelete = false

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
            PickerFilter<Task>(id: "flag.hasDue", label: "Has due", chipColor: AppTheme.mutedText, group: "Flags") { $0.dueAt != nil },
            PickerFilter<Task>(id: "flag.blocked", label: "Blocked", chipColor: AppTheme.destructive, group: "Flags") { $0.isBlocked },
            PickerFilter<Task>(id: "flag.unblocked", label: "Unblocked", chipColor: AppTheme.completed, group: "Flags") { $0.isOpen && !$0.isBlocked }
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
        let query = filterState.searchText.trimmingCharacters(in: .whitespaces)
        return allTasks.filter { task in
            if pendingStatusIds.contains(task.id) { return true }
            guard matched.contains(task.id) else { return false }
            if let range = filterState.dateRange {
                let completedInRange = task.completedAt.map { range.contains($0) } ?? false
                guard completedInRange || range.contains(task.createdAt) else { return false }
            }
            return query.isEmpty || FuzzyMatch.matches(query, in: searchHaystack(task))
        }
    }

    // Fields searched by the fuzzy finder.
    private func searchHaystack(_ task: Task) -> String {
        [task.summary, task.project?.name, task.assignee?.name, task.tags.joined(separator: " ")]
            .compactMap { $0 }.joined(separator: " ")
    }

    // Sortable rows (urgency precomputed), ordered by the per-tab column sort order.
    private var rows: [TaskRow] {
        filteredTasks.map(TaskRow.init).sorted(using: filterState.sortOrder)
    }

    private var selectedTasks: [Task] {
        allTasks.filter { selection.contains($0.id) }
    }

    // MARK: - Bulk actions

    private func bulkComplete() { for t in selectedTasks { t.markCompleted() }; selection.removeAll() }
    private func bulkCancel()   { for t in selectedTasks { t.markCancelled() }; selection.removeAll() }
    private func bulkStarted()  {
        for t in selectedTasks {
            if t.status == .completed { t.unmarkCompleted() } else if t.status == .cancelled { t.unmarkCancelled() }
            t.followUpAt = nil; t.status = .started; t.updatedAt = Date()
        }
        selection.removeAll()
    }
    private func bulkTodo() {
        for t in selectedTasks {
            switch t.status {
            case .completed:       t.unmarkCompleted()
            case .cancelled:       t.unmarkCancelled()
            case .followUpPending: t.followUpAt = nil; t.status = .todo; t.updatedAt = Date()
            default:               t.status = .todo; t.updatedAt = Date()
            }
        }
        selection.removeAll()
    }
    private func bulkDelete() {
        for t in selectedTasks { modelContext.delete(t) }
        selection.removeAll()
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
                Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.secondary)
                TextField("Fuzzy find tasks…", text: $filter.searchText)
                    .textFieldStyle(.plain)
                if !filter.searchText.isEmpty {
                    Button { filter.searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal).padding(.vertical, 6)
            bulkBar
            Divider()
            taskTable
        }
        .background(AppTheme.background)
        .sheet(item: $editingTask) { task in
            TaskEditorSheet(task: task, defaultDate: Date())
        }
        .alert("Delete \(selection.count) task\(selection.count == 1 ? "" : "s")?", isPresented: $confirmingBulkDelete) {
            Button("Delete", role: .destructive) { bulkDelete() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This permanently deletes the selected task\(selection.count == 1 ? "" : "s").") }
        .onChange(of: filterState.activeFilterIds) { pendingStatusIds.removeAll() }
        .onChange(of: filterState.dateRange) { pendingStatusIds.removeAll() }
    }

    private var bulkBar: some View {
        HStack(spacing: 10) {
            Text(selection.isEmpty ? "No selection" : "\(selection.count) selected")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Group {
                Button("Complete") { bulkComplete() }
                Button("Started") { bulkStarted() }
                Button("To do") { bulkTodo() }
                Button("Cancel") { bulkCancel() }
                Button("Delete", role: .destructive) { confirmingBulkDelete = true }
                Button("Clear") { selection.removeAll() }
            }
            .disabled(selection.isEmpty)
        }
        .buttonStyle(.bordered).controlSize(.small)
        .padding(.horizontal).padding(.bottom, 6)
    }

    #if os(macOS)
    private var taskTable: some View {
        @Bindable var filter = filterState
        return Table(rows, selection: $selection, sortOrder: $filter.sortOrder) {
            TableColumn("Summary", value: \.summaryKey) { row in
                HStack(spacing: 4) {
                    if row.task.isBlocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10)).foregroundStyle(AppTheme.destructive)
                            .help("Blocked by an unfinished task")
                    }
                    Text(row.task.summary)
                        .lineLimit(1)
                        .font(AppTheme.bodyFont(size: 13))
                        .foregroundStyle(pendingStatusIds.contains(row.id) ? AppTheme.mutedText : AppTheme.text)
                }
                .contentShape(Rectangle())
                .onTapGesture { editingTask = row.task }
            }
            .width(min: 160, ideal: 300)
            TableColumn("Project", value: \.projectKey) { row in
                Text(row.task.project?.name ?? "").foregroundStyle(AppTheme.project).lineLimit(1)
            }
            .width(min: 80, ideal: 140)
            TableColumn("Status", value: \.statusRank) { row in
                TaskStatusMenu(task: row.task, onBeforeChange: { pendingStatusIds.insert(row.id) }) {
                    TaskStatusIcon(status: row.task.status)
                }
            }
            .width(min: 96, ideal: 130)
            TableColumn("Pri", value: \.priorityRank) { row in
                if row.task.priority != .none {
                    Chip(label: row.task.priority.short, color: priorityColor(row.task.priority))
                }
            }
            .width(min: 40, ideal: 46)
            TableColumn("Due", value: \.dueKey) { row in
                if let due = row.task.dueAt {
                    Text(due, format: .dateTime.month(.abbreviated).day())
                        .foregroundStyle(row.task.isOverdue ? AppTheme.destructive : AppTheme.mutedText)
                }
            }
            .width(min: 60, ideal: 80)
            TableColumn("Urg", value: \.urgency) { row in
                Text(String(format: "%.1f", row.urgency))
                    .font(AppTheme.bodyFont(size: 12)).foregroundStyle(AppTheme.mutedText).monospacedDigit()
            }
            .width(min: 44, ideal: 50)
            TableColumn("Assignee", value: \.assigneeKey) { row in
                Text(row.task.assignee?.name ?? "").foregroundStyle(AppTheme.person).lineLimit(1)
            }
            .width(min: 80, ideal: 120)
            TableColumn("Created", value: \.createdAt) { row in
                Text(row.createdAt, format: .dateTime.month(.abbreviated).day().year())
                    .foregroundStyle(AppTheme.mutedText)
            }
            .width(min: 80, ideal: 100)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if ids.count == 1, let t = allTasks.first(where: { $0.id == ids.first }) {
                Button("Edit…") { editingTask = t }
                Divider()
            }
            Button("Complete") { selection = ids; bulkComplete() }
            Button("To do") { selection = ids; bulkTodo() }
            Button("Cancel") { selection = ids; bulkCancel() }
            Button("Delete", role: .destructive) { selection = ids; confirmingBulkDelete = true }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .animation(.easeInOut(duration: 0.25), value: rows.map(\.id))
    }
    #else
    private var taskTable: some View {
        List(rows) { row in
            TaskRowView(task: row.task, onEdit: { editingTask = row.task })
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
