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
            lane("Today", systemImage: "sun.max", tint: AppTheme.today, tasks: b.today,
                 horizon: .today, derived: dueGroup)
            Divider()
            lane("This Week", systemImage: "calendar", tint: AppTheme.accent, tasks: b.thisWeek, horizon: .thisWeek)
            Divider()
            lane("Maybe", systemImage: "questionmark.circle", tint: AppTheme.mutedText, tasks: b.maybe, horizon: .maybe)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.background)
    }

    /// Tasks that are due today or overdue but unplanned. Derived every render — nothing is written,
    /// so `planHorizon` stays purely manual (see BoardDueGroup).
    private var dueGroup: [Task] {
        BoardDueGroup.members(allTasks, inputs: {
            .init(isOpen: $0.isOpen, needsTriage: $0.needsTriage, isWaiting: $0.isWaiting,
                  isStanding: $0.isStanding, hasHorizon: $0.planHorizon != nil, dueAt: $0.dueAt)
        })
    }

    private func lane(_ title: String, systemImage: String, tint: Color,
                      tasks: [Task], horizon: PlanHorizon,
                      derived: [Task] = []) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.caption).foregroundStyle(tint)
                Text(title).font(AppTheme.bodyFont(size: 12).weight(.semibold)).foregroundStyle(AppTheme.text)
                Text("\(tasks.count + derived.count)")
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
                    if !derived.isEmpty {
                        Text("Due & overdue")
                            .font(AppTheme.bodyFont(size: 10).weight(.semibold))
                            .foregroundStyle(AppTheme.mutedText)
                            .padding(.horizontal, 2).padding(.top, 2)
                        ForEach(laneRows(derived), id: \.item.id) { row in
                            BoardCard(task: row.item, depth: row.depth, isContext: row.isContext,
                                      isDerived: !row.isContext)
                                .onTapGesture(count: 2) {
                                    workspace.focusOrOpen(.task(row.item.persistentModelID))
                                }
                                .contextMenu { derivedMenu(row.item, isContext: row.isContext) }
                        }
                        Divider().padding(.vertical, 4)
                    }
                    if tasks.isEmpty && derived.isEmpty {
                        Text("Drop tasks here.")
                            .font(AppTheme.bodyFont(size: 11))
                            .foregroundStyle(AppTheme.mutedText)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                    }
                    ForEach(laneRows(tasks), id: \.item.id) { row in
                        BoardCard(task: row.item, depth: row.depth, isContext: row.isContext)
                            .draggable(row.item.id.uuidString)
                            .onTapGesture(count: 2) {
                                workspace.focusOrOpen(.task(row.item.persistentModelID))
                            }
                            .contextMenu { cardMenu(row.item, isContext: row.isContext) }
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

    /// Derived cards hold no horizon, so there is nothing to move or remove — the one action is to
    /// turn the date-driven suggestion into a real plan.
    @ViewBuilder private func derivedMenu(_ task: Task, isContext: Bool) -> some View {
        if isContext {
            Text("Shown for context")
        } else {
            Button("Plan it") { place(task, on: .today) }
        }
    }

    @ViewBuilder private func cardMenu(_ task: Task, isContext: Bool) -> some View {
        if isContext {
            // A context row is only here to place its children; it holds no horizon of its own.
            Text("Shown for context")
        } else {
            ForEach(PlanHorizon.allCases, id: \.self) { h in
                if h != task.planHorizon {
                    Button("Move to \(h.displayName)") { place(task, on: h) }
                }
            }
            Divider()
            Button("Remove from board", role: .destructive) { remove(task) }
        }
    }

    // MARK: - Layout

    /// The lane's members laid out as nested rows, with the ancestors needed to place them.
    private func laneRows(_ members: [Task]) -> [BoardRow<Task>] {
        BoardHierarchy.rows(members: members, all: allTasks, id: \.id,
                            parentID: { $0.parent?.id },
                            planSortOrder: \.planSortOrder, treeSortOrder: \.sortOrder)
    }

    private var childrenByParent: [UUID: [UUID]] {
        var map: [UUID: [UUID]] = [:]
        for task in allTasks {
            if let pid = task.parent?.id { map[pid, default: []].append(task.id) }
        }
        return map
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

    /// Placing (or moving) a task takes its whole open subtree with it, so a breakdown never splits
    /// across lanes — which is what keeps an ancestor row unambiguous.
    private func place(_ task: Task, on horizon: PlanHorizon) {
        let targets = BoardHierarchy.placementTargets(
            rootID: task.id, childrenByParent: childrenByParent,
            isOpen: { id in allTasks.first { $0.id == id }?.isOpen ?? false })
        var nextOrder = BoardPlacement.appendOrder(
            existingOrders: allTasks.filter { $0.planHorizon == horizon && !targets.contains($0.id) }
                .map(\.planSortOrder))
        for member in allTasks where targets.contains(member.id) {
            // Triage is a gate: inbox work must be filed before it can be planned.
            guard BoardPlacement.canPlace(isOpen: member.isOpen, needsTriage: member.needsTriage) else { continue }
            member.place(on: horizon)
            member.planSortOrder = nextOrder
            member.updatedAt = Date()
            nextOrder += 1
        }
    }

    /// Removal mirrors placement: the row and its descendants leave, siblings and ancestors stay.
    private func remove(_ task: Task) {
        let targets = BoardHierarchy.placementTargets(
            rootID: task.id, childrenByParent: childrenByParent, isOpen: { _ in true })
        for member in allTasks where targets.contains(member.id) {
            member.place(on: nil)
            member.updatedAt = Date()
        }
    }

    private func clear(_ tasks: [Task]) {
        for task in tasks { remove(task) }
    }
}

// One task on the board: enough to decide, not so much that a lane becomes unreadable.
private struct BoardCard: View {
    @Bindable var task: Task
    var depth: Int = 0
    /// An ancestor shown only to place its children: dimmed, and with no status control to press.
    var isContext: Bool = false
    /// A date-driven suggestion rather than something you planned: accented, and not draggable.
    var isDerived: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if isContext {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 9)).foregroundStyle(AppTheme.mutedText)
                } else {
                    TaskStatusMenu(task: task) { TaskStatusIcon(status: task.status) }
                }
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
        .background(AppTheme.cardRaised.opacity(isContext ? 0.15 : 0.35),
                    in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .leading) {
            // A stripe in the due colour marks a card you cannot drag, so it doesn't look like the
            // planned cards below it.
            if isDerived {
                Rectangle()
                    .fill(task.isOverdue ? AppTheme.destructive : AppTheme.followUp)
                    .frame(width: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }
        }
        .opacity(isContext ? 0.65 : 1)
        .padding(.leading, CGFloat(depth) * 12)
    }
}
