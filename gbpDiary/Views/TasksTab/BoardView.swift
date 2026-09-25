import SwiftUI
import SwiftData

// The planning board: a global, cross-project view of what you intend to do next, in four columns —
// Inbox / Today / This Week / Maybe.
//
// Placement is deliberately **manual**: nothing auto-demotes at a day or week boundary, so Today is
// whatever you last said it was. The partition itself is the pure `BoardPartition` (standing and
// closed tasks excluded; a task still needing triage lands in Inbox whatever its horizon; a reviewed
// task with no horizon is off-board backlog and shows in no column).
//
// Dragging a task to a column sets its `planHorizon` and appends it there; dragging out of Inbox also
// reviews the task, since placing it is the act of triaging it. The diary's DayTaskPanel remains the
// execution view — this is the planning surface.
struct BoardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(WorkspaceModel.self) private var workspace
    @Query(sort: \Task.createdAt) private var allTasks: [Task]

    @State private var dropTarget: PlanHorizon??

    private var buckets: BoardBuckets<Task> {
        BoardPartition.partition(allTasks,
                                 needsTriage: \.needsTriage,
                                 isStanding: \.isStanding,
                                 isOpen: \.isOpen,
                                 horizon: \.planHorizon,
                                 sortOrder: \.planSortOrder)
    }

    var body: some View {
        let b = buckets
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            #if os(macOS)
            HStack(alignment: .top, spacing: 0) {
                column("Inbox", systemImage: "tray", tint: AppTheme.followUp, tasks: b.inbox, horizon: nil)
                Divider()
                column("Today", systemImage: "sun.max", tint: AppTheme.today, tasks: b.today, horizon: .today)
                Divider()
                column("This Week", systemImage: "calendar", tint: AppTheme.accent, tasks: b.thisWeek, horizon: .thisWeek)
                Divider()
                column("Maybe", systemImage: "questionmark.circle", tint: AppTheme.mutedText, tasks: b.maybe, horizon: .maybe)
            }
            #else
            List {
                section("Inbox", b.inbox); section("Today", b.today)
                section("This Week", b.thisWeek); section("Maybe", b.maybe)
            }
            #endif
        }
        .background(AppTheme.background)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Planning board")
                .font(AppTheme.bodyFont(size: 13).weight(.semibold))
                .foregroundStyle(AppTheme.text)
            Text("Drag a task to plan it — placement is manual and never expires")
                .font(AppTheme.bodyFont(size: 11))
                .foregroundStyle(AppTheme.mutedText)
            Spacer()
        }
        .padding(.horizontal).padding(.vertical, 8)
    }

    #if os(macOS)
    /// `horizon == nil` is the Inbox column: it is a source, never a drop target (you leave the inbox
    /// by planning a task, not by dragging back into it).
    private func column(_ title: String, systemImage: String, tint: Color,
                        tasks: [Task], horizon: PlanHorizon?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.caption).foregroundStyle(tint)
                Text(title).font(AppTheme.bodyFont(size: 12).weight(.semibold)).foregroundStyle(AppTheme.text)
                Text("\(tasks.count)")
                    .font(AppTheme.bodyFont(size: 11)).foregroundStyle(AppTheme.mutedText).monospacedDigit()
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if tasks.isEmpty {
                        Text(horizon == nil ? "Nothing to triage." : "Drop tasks here.")
                            .font(AppTheme.bodyFont(size: 11))
                            .foregroundStyle(AppTheme.mutedText)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                    }
                    ForEach(tasks) { task in
                        BoardCard(task: task)
                            .draggable(task.id.uuidString)
                            .onTapGesture(count: 2) { workspace.focusOrOpen(.task(task.persistentModelID)) }
                            .contextMenu { placementMenu(task) }
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(isTargeted(horizon) ? AppTheme.chipBackground(tint) : Color.clear)
        .dropDestination(for: String.self) { items, _ in
            guard let horizon else { return false }
            return place(items, on: horizon)
        } isTargeted: { targeted in
            dropTarget = targeted ? .some(horizon) : nil
        }
    }

    private func isTargeted(_ horizon: PlanHorizon?) -> Bool {
        guard let dropTarget, horizon != nil else { return false }
        return dropTarget == horizon
    }

    @ViewBuilder private func placementMenu(_ task: Task) -> some View {
        ForEach(PlanHorizon.allCases, id: \.self) { h in
            Button(h.displayName) { place(task, on: h) }
        }
        if task.planHorizon != nil {
            Divider()
            Button("Remove from board") { task.planHorizon = nil; task.updatedAt = Date() }
        }
    }
    #endif

    @ViewBuilder private func section(_ title: String, _ tasks: [Task]) -> some View {
        Section(title) {
            ForEach(tasks) { task in BoardCard(task: task) }
        }
    }

    // MARK: - Placement

    private func place(_ ids: [String], on horizon: PlanHorizon) -> Bool {
        let uuids = ids.compactMap(UUID.init(uuidString:))
        let moved = allTasks.filter { uuids.contains($0.id) }
        guard !moved.isEmpty else { return false }
        for task in moved { place(task, on: horizon) }
        return true
    }

    /// Placing a task appends it to the end of the target column. Doing so from the Inbox also marks it
    /// reviewed — deciding when to do something IS the triage decision.
    private func place(_ task: Task, on horizon: PlanHorizon) {
        let existing = allTasks.filter { $0.planHorizon == horizon && $0.id != task.id }
        let shouldReview = BoardPlacement.shouldReview(needsTriage: task.needsTriage)
        task.place(on: horizon)
        task.planSortOrder = BoardPlacement.appendOrder(existingOrders: existing.map(\.planSortOrder))
        if shouldReview { task.markReviewed() }
        task.updatedAt = Date()
    }
}

// One task on the board: enough to decide, not so much that a column becomes unreadable.
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
