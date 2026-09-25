import SwiftUI
import SwiftData

struct TasksView: View {
    @Query(sort: \Task.createdAt) private var allTasks: [Task]
    @Query(sort: \Project.name) private var allProjects: [Project]
    @Query(sort: \Person.name) private var allPeople: [Person]
    // For the net-based "Time" column (focus-block net comes from the canonical TimeLedger).
    @Query private var allFocusBlocks: [FocusBlock]
    @Query private var allConversations: [EmailConversation]
    @Query private var allMeetings: [Minutes]

    @Environment(\.modelContext) private var modelContext
    // Filter state is held on the active workspace tab so it survives navigation and differs per tab.
    @Environment(WorkspaceModel.self) private var workspace
    private var filterState: TasksFilterState { workspace.active.tasksFilter }
    @State private var editingTask: Task? = nil
    @State private var showingAddTask = false
    @State private var pendingStatusIds: Set<UUID> = []
    @State private var selection: Set<UUID> = []
    // Tasks selected but hidden by the current filter — restored to `selection` if the filter reverts.
    @State private var stashedSelection: Set<UUID> = []
    @State private var confirmingBulkDelete = false
    /// True when the width rule closed the panel, so it can reopen when there is room again — but only
    /// if the user didn't close it themselves.
    @State private var autoHidden = false
    /// Last known window width, from WindowWidthReader — drives both auto-hide and the panel's width.
    @State private var windowWidth: CGFloat = 0
    /// Board cards currently selected. Owned here (not in BoardPanel) so the remove target can appear
    /// over this pane exactly when there is something to drop on it.
    @State private var boardSelection: Set<UUID> = []
    @State private var unplanTargeted = false
    /// True while a board card is in flight — what reveals the remove target.
    @State private var boardDragging = false
    @State private var boardDragMonitor = BoardDragMonitor()
    /// Transient note about tasks a bulk add couldn't place (closed ones).
    @State private var lastSkippedMessage: String? = nil
    @State private var triageSelection: Set<UUID> = []
    @State private var triageSkippedMessage: String? = nil
    @State private var confirmingTriageDelete = false

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
        let state = [
            PickerFilter<Task>(id: "preset.incomplete", label: "Incomplete", chipColor: AppTheme.accent, group: "State") { $0.isOpen },
            // The board is the view of what IS planned, so the table only needs the complement.
            PickerFilter<Task>(id: "preset.notOnBoard", label: "Not on board", chipColor: AppTheme.today, group: "State") { !$0.isOnBoard }
        ]
        // "Mine"/"Others" live in the Assignee group so they OR with the per-person assignee filters.
        let me = AppSettingsStore.myPersonID
        let mine = [
            PickerFilter<Task>(id: "preset.mine", label: "Mine", chipColor: AppTheme.person, group: "Assignee") { me != nil && $0.assignee?.id == me },
            PickerFilter<Task>(id: "preset.others", label: "Others", chipColor: AppTheme.person, group: "Assignee") { $0.assignee != nil && $0.assignee?.id != me }
        ]
        let priorities = TaskPriority.allCases.filter { $0 != .none }.map { p in
            PickerFilter<Task>(id: "priority.\(p.rawValue)", label: p.displayName, chipColor: priorityColor(p), group: "Priority") { $0.priority == p }
        }
        let flags = [
            PickerFilter<Task>(id: "flag.overdue", label: "Overdue", chipColor: AppTheme.destructive, group: "Flags") { $0.isOverdue },
            PickerFilter<Task>(id: "flag.dueToday", label: "Due today", chipColor: AppTheme.followUp, group: "Flags") { $0.isDueToday },
            PickerFilter<Task>(id: "flag.hasDue", label: "Has due", chipColor: AppTheme.mutedText, group: "Flags") { $0.dueAt != nil },
            PickerFilter<Task>(id: "flag.blocked", label: "Blocked", chipColor: AppTheme.destructive, group: "Flags") { $0.isBlocked },
            PickerFilter<Task>(id: "flag.unblocked", label: "Unblocked", chipColor: AppTheme.completed, group: "Flags") { $0.isOpen && !$0.isBlocked },
            PickerFilter<Task>(id: "flag.waiting", label: "Waiting", chipColor: AppTheme.mutedText, group: "Flags") { $0.isWaiting },
            PickerFilter<Task>(id: "flag.standing", label: "Standing", chipColor: AppTheme.duration, group: "Flags") { $0.isStanding },
            // Reveals the Inbox inside the Reviewed table — the route a fresh capture takes to the
            // planning board, since placing it there marks it reviewed.
            PickerFilter<Task>(id: "flag.needsTriage", label: "Needs triage", chipColor: AppTheme.followUp, group: "Flags") { $0.isOpen && $0.needsTriage }
        ]
        return state + status + priorities + flags + projects + assignees + mine + source
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
        let showWaiting = filterState.activeFilterIds.contains("flag.waiting")
        let showStanding = filterState.activeFilterIds.contains("flag.standing")
        let showNeedsTriage = filterState.activeFilterIds.contains("flag.needsTriage")
        return allTasks.filter { task in
            if pendingStatusIds.contains(task.id) { return true }
            // Untriaged / waiting / standing tasks are each hidden until their own control reveals
            // them — see TaskTableVisibility for why.
            if TaskTableVisibility.isHidden(isOpen: task.isOpen, needsTriage: task.needsTriage,
                                            isWaiting: task.isWaiting, isStanding: task.isStanding,
                                            showWaiting: showWaiting, showStanding: showStanding,
                                            showNeedsTriage: showNeedsTriage) {
                return false
            }
            guard matched.contains(task.id) else { return false }
            if let range = filterState.dateRange, !range.contains(task.createdAt) {
                return false   // date presets/range match the captured (created) date
            }
            return query.isEmpty || FuzzyMatch.matches(query, in: searchHaystack(task))
        }
    }

    // Fields searched by the fuzzy finder.
    private func searchHaystack(_ task: Task) -> String {
        [task.summary, task.project?.name, task.assignee?.name, task.tags.joined(separator: " ")]
            .compactMap { $0 }.joined(separator: " ")
    }

    // Sortable rows (urgency precomputed), laid out as a parent → child task tree. The focus-block net map
    // is computed once here (one canonical-ledger pass, like the Timesheet) and drives the Time column.
    //
    // Rows are built for *every* task, not just the matches, because a matched subtask's ancestors are
    // shown as dimmed context (so you can see where it sits) — exactly the ProjectsView treatment.
    // `ProjectHierarchy.rows` is generic and pure, so it is reused here rather than reimplemented.
    private var hierarchyRows: [HierarchyRow<TaskRow>] {
        let blockNet = TimeLedgerProjection.blockNet(focusBlocks: allFocusBlocks, tasks: allTasks,
                                                     conversations: allConversations, meetings: allMeetings)
        let comparator = filterState.sortOrder
        return ProjectHierarchy.rows(
            all: allTasks.map { TaskRow($0, blockNet: blockNet) },
            id: \.id, parentID: { $0.task.parent?.id },
            matched: Set(filteredTasks.map(\.id)),
            sortSiblings: { $0.sorted(using: comparator) })
    }

    private var rows: [TaskRow] { hierarchyRows.map(\.item) }

    /// Three lanes want ~560–780pt (measured). Give the panel what is left after the sidebar and a
    /// readable table, clamped to that range, so a narrow window shrinks the panel before the table.
    private var boardPanelWidth: CGFloat {
        let availableForPanel = windowWidth - 200 - 420   // sidebar, then a usable table
        return min(780, max(560, availableForPanel))
    }

    // The Inbox: open, top-level tasks awaiting Review, oldest first (clear the backlog).
    private var triageTasks: [Task] {
        allTasks
            .filter { $0.needsTriage && $0.parent == nil && $0.isOpen }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var selectedTasks: [Task] {
        allTasks.filter { selection.contains($0.id) }
    }

    // MARK: - Bulk actions

    // Clears the active selection and the stashed (filtered-out) set — acting on the selection ends
    // the retain-and-restore cycle so a later filter change won't resurrect it.
    /// Place every selected task (and its open subtree) in a lane. Closed tasks can't be planned, so
    /// they are skipped and reported rather than silently doing nothing.
    private func bulkPlace(on horizon: PlanHorizon) {
        let chosen = allTasks.filter { selection.contains($0.id) }
        let eligible = chosen.filter { BoardPlacement.canPlace(isOpen: $0.isOpen, needsTriage: $0.needsTriage) }
        let closed = chosen.filter { !$0.isOpen }.count
        let untriaged = chosen.filter { $0.isOpen && $0.needsTriage }.count

        var childrenByParent: [UUID: [UUID]] = [:]
        for task in allTasks {
            if let pid = task.parent?.id { childrenByParent[pid, default: []].append(task.id) }
        }
        var targets: Set<UUID> = []
        for task in eligible {
            targets.formUnion(BoardHierarchy.placementTargets(
                rootID: task.id, childrenByParent: childrenByParent,
                isOpen: { id in allTasks.first { $0.id == id }?.isOpen ?? false }))
        }
        var nextOrder = BoardPlacement.appendOrder(
            existingOrders: allTasks.filter { $0.planHorizon == horizon && !targets.contains($0.id) }
                .map(\.planSortOrder))
        for member in allTasks where targets.contains(member.id) {
            guard BoardPlacement.canPlace(isOpen: member.isOpen, needsTriage: member.needsTriage) else { continue }
            member.place(on: horizon)
            member.planSortOrder = nextOrder
            member.updatedAt = Date()
            nextOrder += 1
        }
        // Say which rule skipped what: "needs triage" is actionable, "completed" is not.
        var notes: [String] = []
        if untriaged > 0 { notes.append("\(untriaged) need\(untriaged == 1 ? "s" : "") triage") }
        if closed > 0 { notes.append("\(closed) completed") }
        lastSkippedMessage = notes.isEmpty ? nil : notes.joined(separator: ", ") + " skipped"
        workspace.active.boardPanelShown = true   // show where the tasks just went
    }

    /// Shown only while board cards are selected, so it costs no space the rest of the time. An
    /// overlay rather than a destination on the pane itself: the pane contains the table's draggable
    /// rows, and making a container of drag sources accept drops wedges AppKit in a dragging-update
    /// loop. This view contains nothing draggable.
    @ViewBuilder private var removeDropTarget: some View {
        if boardDragging {
            VStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 24))
                Text("Drop here to remove")
                    .font(AppTheme.bodyFont(size: 13).weight(.semibold))
                Text(boardSelection.count > 1 ? "\(boardSelection.count) selected" : "from the board")
                    .font(AppTheme.bodyFont(size: 11))
                    .foregroundStyle(AppTheme.mutedText)
            }
            .padding(22)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(unplanTargeted ? AppTheme.destructive : AppTheme.mutedText.opacity(0.5),
                                  style: StrokeStyle(lineWidth: unplanTargeted ? 2 : 1, dash: [6, 4]))
            }
            .foregroundStyle(unplanTargeted ? AppTheme.destructive : AppTheme.mutedText)
            .shadow(radius: 8)
            .dropDestination(for: String.self) { payloads, _ in
                unplan(BoardDragPayload.decode(payloads))
            } isTargeted: { unplanTargeted = $0 }
            .transition(.opacity)
        }
    }

    /// Clears the horizon of every dragged task and its descendants — the same subtree rule as the
    /// card's "Remove from board", so the two paths agree.
    @discardableResult
    private func unplan(_ ids: [UUID]) -> Bool {
        let dragged = allTasks.filter { ids.contains($0.id) }
        guard !dragged.isEmpty else { return false }
        var childrenByParent: [UUID: [UUID]] = [:]
        for task in allTasks {
            if let pid = task.parent?.id { childrenByParent[pid, default: []].append(task.id) }
        }
        var targets: Set<UUID> = []
        for task in dragged {
            targets.formUnion(TaskParenting.subtree(of: task.id, childrenByParent: childrenByParent))
        }
        for task in allTasks where targets.contains(task.id) && task.isOnBoard {
            task.place(on: nil)
            task.updatedAt = Date()
        }
        boardSelection.removeAll()
        boardDragging = false
        return true
    }

    private func clearSelection() { selection.removeAll(); stashedSelection.removeAll() }

    private func bulkComplete() { for t in selectedTasks { t.markCompleted() }; clearSelection() }
    private func bulkCancel()   { for t in selectedTasks { t.markCancelled() }; clearSelection() }
    private func bulkStarted()  {
        for t in selectedTasks {
            if t.status == .completed { t.unmarkCompleted() } else if t.status == .cancelled { t.unmarkCancelled() }
            t.followUpAt = nil; t.status = .started; t.updatedAt = Date()
        }
        clearSelection()
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
        clearSelection()
    }
    private func bulkDelete() {
        for t in selectedTasks { modelContext.delete(t) }
        clearSelection()
    }

    // Opens the double-clicked row's task in its own workspace tab (like Projects/People). `rows` is the
    // sorted display order, matching NSTableView. Editing stays available via the detail page + context menu.
    private func openRow(_ index: Int) {
        guard rows.indices.contains(index) else { return }
        workspace.focusOrOpen(.task(rows[index].task.persistentModelID))
    }

    var body: some View {
        @Bindable var filter = filterState
        // Laid out by hand rather than with `.inspector()`: the inspector draws a translucent chrome
        // band over the top of the page (it presents inside WorkspaceView's NavigationSplitView detail),
        // which covered the view-mode buttons. A plain HStack negotiates width with nobody.
        return HStack(spacing: 0) {
            VStack(spacing: 0) {
                viewModePicker
                Divider()
                switch filter.viewMode {
                case .reviewed:   reviewedPane
                case .triage:     triagePane
                }
            }
            .frame(minWidth: 360, maxWidth: .infinity)
            .background(AppTheme.background)
            .overlay { removeDropTarget }
            // NOTE: deliberately NOT a drop destination. The table's own rows drag `String`, so
            // accepting drops here made a row-drag enter its own destination and wedge AppKit in a
            // dragging-update loop — an unrecoverable stuck drag. Removal by drag lives on
            // BoardPanel's remove strip, which contains no drag sources.

            if workspace.active.boardPanelShown {
                Divider()
                BoardPanel(selection: $boardSelection, isDragging: $boardDragging)
                    .frame(width: boardPanelWidth)
            }
        }
        // Auto-hide keys off the WINDOW width, never the content column: hiding the panel widens the
        // content, which would satisfy the show condition again and oscillate. Hysteresis keeps the two
        // conditions from chasing each other, and the write is deferred out of the update pass.
        .background(WindowWidthReader { width in
            windowWidth = width
            if width < 1150, workspace.active.boardPanelShown {
                workspace.active.boardPanelShown = false
                autoHidden = true
            } else if width > 1250, autoHidden {
                workspace.active.boardPanelShown = true
                autoHidden = false
            }
        })
        .toolbar {
            ToolbarItem {
                Button { showingAddTask = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editingTask) { task in
            TaskEditorSheet(task: task, defaultDate: Date())
        }
        .sheet(isPresented: $showingAddTask) {
            TaskEditorSheet(task: nil, defaultDate: Date())
        }
        .alert("Delete \(triageSelection.count) task\(triageSelection.count == 1 ? "" : "s")?",
               isPresented: $confirmingTriageDelete) {
            Button("Delete", role: .destructive) { bulkDeleteTriage() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This permanently deletes the selected task\(triageSelection.count == 1 ? "" : "s").") }
        .alert("Delete \(selection.count) task\(selection.count == 1 ? "" : "s")?", isPresented: $confirmingBulkDelete) {
            Button("Delete", role: .destructive) { bulkDelete() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This permanently deletes the selected task\(selection.count == 1 ? "" : "s").") }
        .onChange(of: filterState.activeFilterIds) { pendingStatusIds.removeAll() }
        .onAppear {
            // Mouse-up ends every drag, however it finished, so the target never gets stranded on screen.
            boardDragMonitor.onEnded = { boardDragging = false }
            boardDragMonitor.start()
        }
        .onDisappear { boardDragMonitor.stop() }
        .onChange(of: filterState.dateRange) { pendingStatusIds.removeAll() }
        // Keep the selection in sync with filtering: drop now-hidden tasks (restorable later), restore
        // reappearing ones. Keyed on the visible id set, so pure re-sorts and manual selection changes
        // (same ids) don't trigger it.
        .onChange(of: Set(rows.map(\.id))) { _, visible in
            let result = TableSelectionReconcile.reconcile(
                selection: selection, stashed: stashedSelection, visible: visible)
            if result.selection != selection { selection = result.selection }
            if result.stashed != stashedSelection { stashedSelection = result.stashed }
        }
    }

    // The Reviewed / Triage / Side-by-side switcher, with a live inbox count on the Triage tab.
    private var viewModePicker: some View {
        @Bindable var filter = filterState
        return HStack(spacing: 10) {
            Picker("", selection: $filter.viewMode) {
                ForEach(TaskViewMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            // Sits with Reviewed/Triage rather than across the page: it is a separate toggle, not a
            // third mode (the board shows alongside whichever list you are in).
            Button {
                autoHidden = false          // an explicit choice outranks the width rule
                workspace.active.boardPanelShown.toggle()
            } label: {
                Label("Board", systemImage: "rectangle.split.3x1")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(workspace.active.boardPanelShown ? AppTheme.accent : AppTheme.mutedText)
            .help("Show the planning board beside the table")
            if !triageTasks.isEmpty {
                Text("\(triageTasks.count) to review")
                    .font(.caption).foregroundStyle(AppTheme.accent)
            }
            Spacer()
        }
        .padding(.horizontal).padding(.vertical, 6)
    }

    // The normal filterable table (search/filters/columns/bulk), scoped to triaged tasks.
    private var reviewedPane: some View {
        @Bindable var filter = filterState
        return VStack(spacing: 0) {
            TasksToolbar(filters: taskFilters, filter: filter)
            bulkBar
            Divider()
            taskTable
        }
    }

    // The inbox: untriaged tasks with inline quick-set + Reviewed.
    private var triagePane: some View {
        Group {
            if triageTasks.isEmpty {
                ContentUnavailableView("Inbox clear", systemImage: "tray",
                                       description: Text("No tasks to review."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    triageBulkBar
                    Divider()
                    List(selection: $triageSelection) {
                        // Overdue captures can't reach the board (triage is a gate), so this is the
                        // only place they surface. FIFO survives within the backlog below.
                        if !triageDueTasks.isEmpty {
                            Section("Due & overdue") {
                                ForEach(triageDueTasks) { task in triageRow(task) }
                            }
                            Section("Inbox") {
                                ForEach(triageBacklogTasks) { task in triageRow(task) }
                            }
                        } else {
                            ForEach(triageTasks) { task in triageRow(task) }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .background(AppTheme.background)
    }

    /// The inbox's own bulk bar. Mark-reviewed honours the same rule as the row button — a task needs
    /// a project first — and reports what it skipped rather than appearing to do nothing.
    private var triageBulkBar: some View {
        BulkActionBar(count: triageSelection.count, onClear: { triageSelection.removeAll() }) {
            Button("Mark reviewed") { bulkMarkReviewed() }
            Button("Cancel") { selectedTriageTasks.forEach { $0.markCancelled() }; triageSelection.removeAll() }
            Button("Delete", role: .destructive) { confirmingTriageDelete = true }
        }
        .overlay(alignment: .trailing) {
            if let note = triageSkippedMessage {
                Text(note)
                    .font(.caption).foregroundStyle(AppTheme.mutedText)
                    .padding(.trailing, 12)
            }
        }
    }

    @ViewBuilder private func triageRow(_ task: Task) -> some View {
        TaskTriageRow(task: task, onEdit: { editingTask = task })
            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// Inbox tasks that are already due or overdue, most overdue first. Waiting and standing work is
    /// excluded by the same rule the board uses.
    private var triageDueTasks: [Task] {
        BoardDueGroup.members(triageTasks, inputs: {
            .init(isOpen: $0.isOpen, needsTriage: false,   // these ARE the inbox; triage isn't the filter here
                  isWaiting: $0.isWaiting, isStanding: $0.isStanding,
                  hasHorizon: false, dueAt: $0.dueAt)
        })
    }

    private var triageBacklogTasks: [Task] {
        let due = Set(triageDueTasks.map(\.id))
        return triageTasks.filter { !due.contains($0.id) }
    }

    private var selectedTriageTasks: [Task] {
        triageTasks.filter { triageSelection.contains($0.id) }
    }

    private func bulkMarkReviewed() {
        let chosen = selectedTriageTasks
        let eligible = chosen.filter { $0.project != nil }
        for task in eligible { task.markReviewed() }
        let skipped = chosen.count - eligible.count
        triageSkippedMessage = skipped > 0
            ? "\(skipped) still need\(skipped == 1 ? "s" : "") a project"
            : nil
        triageSelection.removeAll()
    }

    private func bulkDeleteTriage() {
        for task in selectedTriageTasks {
            workspace.closeEntity(task.persistentModelID)
            modelContext.delete(task)
        }
        triageSelection.removeAll()
        triageSkippedMessage = nil
    }

    private var bulkBar: some View {
        BulkActionBar(count: selection.count, onClear: { clearSelection() }) {
            Button("Complete") { bulkComplete() }
            Button("Started") { bulkStarted() }
            Button("To do") { bulkTodo() }
            Button("Cancel") { bulkCancel() }
            Menu("Add to board") {
                ForEach(PlanHorizon.allCases, id: \.self) { h in
                    Button(h.displayName) { bulkPlace(on: h) }
                }
            }
            Button("Delete", role: .destructive) { confirmingBulkDelete = true }
        }
        .overlay(alignment: .trailing) {
            // Closed tasks can't be planned, so say so rather than appearing to do nothing.
            if let skipped = lastSkippedMessage {
                Text(skipped)
                    .font(.caption).foregroundStyle(AppTheme.mutedText)
                    .padding(.trailing, 12)
            }
        }
    }

    #if os(macOS)
    private var taskTable: some View {
        @Bindable var filter = filterState
        // Computed once per render and captured by the cell closures below. Reading it through a
        // computed property instead would re-run the whole hierarchy (and its ledger pass) per cell.
        let hierarchy = hierarchyRows
        let meta = Dictionary(hierarchy.map { ($0.item.id, (depth: $0.depth, isMatch: $0.isMatch)) },
                              uniquingKeysWith: { first, _ in first })
        // Indentation / dimming for a row (context ancestors are dimmed so matches stand out).
        func level(_ row: TaskRow) -> Int { meta[row.id]?.depth ?? 0 }
        func dim(_ row: TaskRow) -> Double { (meta[row.id]?.isMatch ?? true) ? 1 : 0.5 }
        return Table(of: TaskRow.self, selection: $selection, sortOrder: $filter.sortOrder) {
            TableColumn("Summary", value: \.summaryKey) { row in
                HStack(spacing: 4) {
                    if level(row) > 0 {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 9))
                            .foregroundStyle(AppTheme.mutedText)
                    }
                    if row.task.isBlocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10)).foregroundStyle(AppTheme.destructive)
                            .help("Blocked by an unfinished task")
                    }
                    if row.task.isWaiting {
                        Image(systemName: "clock.badge.questionmark")
                            .font(.system(size: 10)).foregroundStyle(AppTheme.mutedText)
                            .help("Waiting until a later date")
                    }
                    if row.task.recurrenceRule != nil {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10)).foregroundStyle(AppTheme.mutedText)
                            .help("Repeats")
                    }
                    if row.task.isStanding {
                        Image(systemName: "infinity")
                            .font(.system(size: 10)).foregroundStyle(AppTheme.duration)
                            .help("Standing task — perpetual, never completes")
                    }
                    Text(row.task.summary)
                        .lineLimit(1)
                        .font(AppTheme.bodyFont(size: 13))
                        .italic(row.task.isOnBoard)
                        .foregroundStyle(row.task.isOnBoard || pendingStatusIds.contains(row.id)
                                         ? AppTheme.mutedText : AppTheme.text)
                }
                .padding(.leading, CGFloat(level(row)) * 16)
                .opacity(dim(row))
            }
            .width(min: 160, ideal: 300)
            TableColumn("Project", value: \.projectKey) { row in
                Text(row.task.project?.name ?? "").foregroundStyle(AppTheme.project).lineLimit(1)
                    .opacity(dim(row))
            }
            .width(min: 80, ideal: 140)
            TableColumn("Status", value: \.statusRank) { row in
                TaskStatusMenu(task: row.task, onBeforeChange: { pendingStatusIds.insert(row.id) }) {
                    TaskStatusIcon(status: row.task.status)
                }
                .opacity(dim(row))
            }
            .width(min: 96, ideal: 130)
            TableColumn("Pri", value: \.priorityRank) { row in
                if row.task.priority != .none {
                    Chip(label: row.task.priority.short, color: priorityColor(row.task.priority))
                        .opacity(dim(row))
                }
            }
            .width(min: 40, ideal: 46)
            TableColumn("Urg", value: \.urgency) { row in
                Text(String(format: "%.1f", row.urgency))
                    .font(AppTheme.bodyFont(size: 12)).foregroundStyle(AppTheme.mutedText).monospacedDigit()
                    .opacity(dim(row))
            }
            .width(min: 44, ideal: 50)
            TableColumn("Time", value: \.timeSpentHours) { row in
                Text(row.timeSpentHours > 0 ? TimeFormat.hours(row.timeSpentHours) : "")
                    .font(AppTheme.bodyFont(size: 12)).foregroundStyle(AppTheme.duration).monospacedDigit()
                    .opacity(dim(row))
            }
            .width(min: 50, ideal: 64)
            TableColumn("Assignee", value: \.assigneeKey) { row in
                Text(row.task.assignee?.name ?? "").foregroundStyle(AppTheme.person).lineLimit(1)
                    .opacity(dim(row))
            }
            .width(min: 80, ideal: 120)
            TableColumn("Created", value: \.createdAt) { row in
                Text(row.createdAt, format: .dateTime.month(.abbreviated).day().year())
                    .foregroundStyle(AppTheme.mutedText)
                    .opacity(dim(row))
            }
            .width(min: 80, ideal: 100)
            TableColumn("Due", value: \.dueKey) { row in
                if let due = row.task.dueAt {
                    Text(due, format: .dateTime.month(.abbreviated).day())
                        .foregroundStyle(row.task.isOverdue ? AppTheme.destructive : AppTheme.mutedText)
                        .opacity(dim(row))
                }
            }
            .width(min: 60, ideal: 80)
            TableColumn("Scheduled", value: \.scheduledKey) { row in
                if let scheduled = row.task.scheduledAt {
                    Text(scheduled, format: .dateTime.month(.abbreviated).day())
                        .foregroundStyle(AppTheme.mutedText)
                        .opacity(dim(row))
                }
            }
            .width(min: 60, ideal: 80)
        } rows: {
            // Spiked before building on it: a TableRow drag carries the WHOLE selection, including a
            // non-contiguous one — so dragging into a lane is a first-class way to plan, not just a
            // single-task shortcut.
            ForEach(hierarchy.map(\.item)) { row in
                TableRow(row).draggable(row.task.id.uuidString)
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if ids.count == 1, let t = allTasks.first(where: { $0.id == ids.first }) {
                Button("Edit…") { editingTask = t }
                Divider()
            }
            Menu("Add to board") {
                ForEach(PlanHorizon.allCases, id: \.self) { h in
                    Button(h.displayName) { selection = ids; bulkPlace(on: h) }
                }
            }
            Divider()
            Button("Complete") { selection = ids; bulkComplete() }
            Button("To do") { selection = ids; bulkTodo() }
            Button("Cancel") { selection = ids; bulkCancel() }
            Button("Delete", role: .destructive) { selection = ids; confirmingBulkDelete = true }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .onTableRowDoubleClick { openRow($0) }
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
