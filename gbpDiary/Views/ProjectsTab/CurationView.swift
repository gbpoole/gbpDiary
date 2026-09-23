import SwiftUI
import SwiftData

// The curation stepper: a linear walk over one root project and its active subprojects, one project at
// a time, for working through neglected task lists at scale.
//
// The walk order is the pure `CurationWalk.order` (root first, active subprojects depth-first,
// completed subtrees pruned) recomputed from live data, and the advance gate is the pure
// `ProjectCurationRules` — a project can't be marked tasks-reviewed while any of its open tasks still
// needs triage. Position lives on the workspace tab, so switching tabs doesn't restart the session.
struct CurationView: View {
    let root: Project

    @Environment(\.modelContext) private var modelContext
    @Environment(WorkspaceModel.self) private var workspace
    @Query(sort: \Project.name) private var allProjects: [Project]
    @Query(sort: \Task.createdAt) private var allTasks: [Task]

    @State private var subtreeCollapsedIds: Set<UUID> = []
    @FocusState private var focusedTaskId: UUID?

    // MARK: - Walk

    private var walk: [Project] {
        CurationWalk.order(rootID: root.id, all: allProjects, id: \.id,
                           parentID: { $0.parent?.id }, isActive: { !$0.isCompleted },
                           sortSiblings: { $0.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } })
    }

    private var index: Int { min(max(0, workspace.active.curationIndex), max(0, walk.count - 1)) }
    private var current: Project? { walk.indices.contains(index) ? walk[index] : nil }
    private var isLast: Bool { index >= walk.count - 1 }

    // MARK: - Tasks of the current project

    private func openTasks(of project: Project) -> [Task] {
        allTasks.filter { $0.project?.id == project.id && $0.isOpen && !$0.isStanding }
    }

    private func rootTasks(of project: Project) -> [Task] {
        openTasks(of: project).filter { $0.parent == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private func untriaged(of project: Project) -> [Task] {
        openTasks(of: project).filter { $0.needsTriage }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func triageFlags(of project: Project) -> [Bool] {
        openTasks(of: project).map(\.needsTriage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal).padding(.top, 12).padding(.bottom, 4)
            DayActionBar(items: actionItems)
            ScrollView {
                if let project = current {
                    VStack(alignment: .leading, spacing: 0) {
                        inboxSection(project)
                        taskSection(project)
                        StandingTasksSection(project: project)
                    }
                    .padding(.bottom, 28)
                    .id(project.id)   // reset per-project view state as the walk advances
                } else {
                    Text("Nothing to curate — this project has no active subprojects.")
                        .foregroundStyle(AppTheme.mutedText)
                        .padding()
                }
            }
        }
        .background(AppTheme.background)
        .navigationTitle("Curate: \(root.name)")
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(current?.name ?? root.name)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.text)
                if let project = current, project.id != root.id {
                    Chip(label: "subproject of \(project.parent?.name ?? root.name)", color: AppTheme.project)
                }
                Spacer()
                Text(walk.isEmpty ? "—" : "\(index + 1) of \(walk.count)")
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundStyle(AppTheme.mutedText)
                    .monospacedDigit()
            }
            if let project = current {
                let pending = ProjectCurationRules.unreviewedCount(openTaskNeedsTriage: triageFlags(of: project))
                HStack(spacing: 8) {
                    if pending > 0 {
                        Chip(label: "\(pending) to review", color: AppTheme.followUp)
                    } else {
                        Chip(label: "All reviewed", color: AppTheme.completed)
                    }
                    if let stamp = project.tasksReviewedAt {
                        Text("Last reviewed \(stamp.formatted(.dateTime.day().month(.abbreviated).year()))")
                            .font(AppTheme.bodyFont(size: 11))
                            .foregroundStyle(AppTheme.mutedText)
                    } else {
                        Text("Never reviewed")
                            .font(AppTheme.bodyFont(size: 11))
                            .foregroundStyle(AppTheme.mutedText)
                    }
                }
            }
        }
    }

    private var actionItems: [DayActionItem] {
        var items: [DayActionItem] = []
        if index > 0 {
            items.append(DayActionItem(id: "prev", systemName: "chevron.left", color: AppTheme.mutedText,
                                       tooltip: "Previous project") { step(-1) })
        }
        if let project = current {
            let canReview = ProjectCurationRules.canMarkTasksReviewed(openTaskNeedsTriage: triageFlags(of: project))
            items.append(DayActionItem(id: "review",
                                       systemName: isLast ? "checkmark.circle" : "checkmark.circle.fill",
                                       color: canReview ? AppTheme.completed : AppTheme.mutedText,
                                       tooltip: canReview
                                       ? (isLast ? "Mark reviewed and finish" : "Mark reviewed and continue")
                                       : "Review every task below first") {
                                           guard canReview else { return }
                                           markReviewed(project)
                                       })
        }
        if !isLast {
            items.append(DayActionItem(id: "skip", systemName: "chevron.right", color: AppTheme.mutedText,
                                       tooltip: "Skip without marking reviewed") { step(1) })
        }
        items.append(DayActionItem(id: "open", systemName: "folder", color: AppTheme.project,
                                   tooltip: "Open this project's page") {
            if let project = current { workspace.openInNewTab(.project(project.persistentModelID)) }
        })
        return items
    }

    // MARK: - Sections

    @ViewBuilder private func inboxSection(_ project: Project) -> some View {
        let inbox = untriaged(project: project)
        if !inbox.isEmpty {
            DaySectionHeader(title: "To review (\(inbox.count))")
            VStack(alignment: .leading, spacing: 4) {
                ForEach(inbox) { task in
                    TaskTriageRow(task: task,
                                  onEdit: { workspace.focusOrOpen(.task(task.persistentModelID)) })
                }
            }
            .padding(.horizontal)
        }
    }

    private func untriaged(project: Project) -> [Task] { untriaged(of: project) }

    @ViewBuilder private func taskSection(_ project: Project) -> some View {
        let roots = rootTasks(of: project)
        DaySectionHeader(title: "Open tasks (\(openTasks(of: project).count))")
        VStack(alignment: .leading, spacing: 4) {
            if roots.isEmpty {
                Text("No open tasks.")
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundStyle(AppTheme.mutedText)
                    .padding(.horizontal)
            } else {
                TaskSubtreeView(
                    tasks: roots,
                    collapsedIds: $subtreeCollapsedIds,
                    focusedId: $focusedTaskId,
                    onEdit: { workspace.focusOrOpen(.task($0.persistentModelID)) },
                    onMakeSubtask: { dragged, target in dragged.parent = target },
                    onPromote: { child in child.parent = nil },
                    onDelete: { modelContext.delete($0) }
                )
            }
            TaskBreakdownField(parent: nil, project: project, text: breakdownDraft(for: project))
        }
    }

    // MARK: - Actions

    /// Drafts are keyed by the project being curated, so stepping between projects keeps each outline.
    private func breakdownDraft(for project: Project) -> Binding<String> {
        Binding(get: { workspace.active.breakdownDrafts[project.id] ?? "" },
                set: { workspace.active.breakdownDrafts[project.id] = $0 })
    }

    private func step(_ delta: Int) {
        workspace.active.curationIndex = min(max(0, index + delta), max(0, walk.count - 1))
    }

    /// Stamps the project reviewed and moves on. The per-task flags are already clear — the gate above
    /// requires it — so this records the project-level stamp only.
    private func markReviewed(_ project: Project) {
        project.tasksReviewedAt = Date()
        project.updatedAt = Date()
        if isLast {
            workspace.active.curationIndex = 0
            workspace.navigate(to: .projects)
        } else {
            step(1)
        }
    }
}
