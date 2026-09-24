import SwiftUI
import SwiftData

// The planning board, hosted as a panel beside the Tasks table (see TasksView's `.inspector`).
//
// Three lanes — Today / This Week / Maybe. There is no Inbox lane: tasks arrive from the table next
// door, where untriaged work is revealed by its own filter, so placing a task IS the triage act.
// Placement is deliberately manual and never expires; nothing auto-demotes at a day or week boundary.
struct BoardPanel: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(WorkspaceModel.self) private var workspace
    @Query(sort: \Task.createdAt) private var allTasks: [Task]

    @State private var dropTarget: PlanHorizon?

    private var buckets: BoardBuckets<Task> {
        BoardPartition.partition(allTasks, isOpen: \.isOpen,
                                 horizon: \.planHorizon, sortOrder: \.planSortOrder)
    }

    var body: some View {
        let b = buckets
        HStack(alignment: .top, spacing: 0) {
            lane("Today", systemImage: "sun.max", tint: AppTheme.today, tasks: b.today, horizon: .today)
            Divider()
            lane("This Week", systemImage: "calendar", tint: AppTheme.accent, tasks: b.thisWeek, horizon: .thisWeek)
            Divider()
            lane("Maybe", systemImage: "questionmark.circle", tint: AppTheme.mutedText, tasks: b.maybe, horizon: .maybe)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.background)
    }

    private func lane(_ title: String, systemImage: String, tint: Color,
                      tasks: [Task], horizon: PlanHorizon) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.caption).foregroundStyle(tint)
                Text(title).font(AppTheme.bodyFont(size: 12).weight(.semibold)).foregroundStyle(AppTheme.text)
                Text("\(tasks.count)")
                    .font(AppTheme.bodyFont(size: 11)).foregroundStyle(AppTheme.mutedText).monospacedDigit()
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .contextMenu {
                if !tasks.isEmpty {
                    Button("Clear lane", role: .destructive) { clear(tasks) }
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if tasks.isEmpty {
                        Text("Drop tasks here.")
                            .font(AppTheme.bodyFont(size: 11))
                            .foregroundStyle(AppTheme.mutedText)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                    }
                    ForEach(tasks) { task in
                        BoardCard(task: task)
                            .draggable(task.id.uuidString)
                            .onTapGesture(count: 2) { workspace.focusOrOpen(.task(task.persistentModelID)) }
                            .contextMenu { cardMenu(task) }
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 180, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(dropTarget == horizon ? AppTheme.chipBackground(tint) : Color.clear)
        .dropDestination(for: String.self) { items, _ in
            place(ids: items, on: horizon)
        } isTargeted: { targeted in
            dropTarget = targeted ? horizon : (dropTarget == horizon ? nil : dropTarget)
        }
    }

    @ViewBuilder private func cardMenu(_ task: Task) -> some View {
        ForEach(PlanHorizon.allCases, id: \.self) { h in
            if h != task.planHorizon {
                Button("Move to \(h.displayName)") { place(task, on: h) }
            }
        }
        Divider()
        Button("Remove from board", role: .destructive) { remove(task) }
    }

    // MARK: - Placement

    @discardableResult
    private func place(ids: [String], on horizon: PlanHorizon) -> Bool {
        let uuids = Set(ids.compactMap(UUID.init(uuidString:)))
        let moved = allTasks.filter { uuids.contains($0.id) }
        guard !moved.isEmpty else { return false }
        for task in moved { place(task, on: horizon) }
        return true
    }

    private func place(_ task: Task, on horizon: PlanHorizon) {
        let existing = allTasks.filter { $0.planHorizon == horizon && $0.id != task.id }
        let shouldReview = BoardPlacement.shouldReview(needsTriage: task.needsTriage)
        task.place(on: horizon)
        task.planSortOrder = BoardPlacement.appendOrder(existingOrders: existing.map(\.planSortOrder))
        if shouldReview { task.markReviewed() }
        task.updatedAt = Date()
    }

    private func remove(_ task: Task) {
        task.place(on: nil)
        task.updatedAt = Date()
    }

    private func clear(_ tasks: [Task]) {
        for task in tasks { remove(task) }
    }
}

// One task on the board: enough to decide, not so much that a lane becomes unreadable.
private struct BoardCard: View {
    @Bindable var task: Task

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                TaskStatusMenu(task: task) { TaskStatusIcon(status: task.status) }
                Text(task.summary)
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundStyle(AppTheme.text)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            HStack(spacing: 4) {
                if task.isStanding {
                    Image(systemName: "infinity").font(.system(size: 9)).foregroundStyle(AppTheme.duration)
                }
                if let project = task.project {
                    Chip(label: project.name, color: AppTheme.project)
                }
                if task.priority != .none {
                    Chip(label: task.priority.short, color: AppTheme.followUp)
                }
                if let due = task.dueAt {
                    Chip(label: due.formatted(.dateTime.day().month(.abbreviated)),
                         color: task.isOverdue ? AppTheme.destructive : AppTheme.mutedText)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardRaised.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
    }
}
