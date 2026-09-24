import SwiftUI
import SwiftData

// The `.task(...)` workspace tab — a page-styled detail view for one Task (opened by double-clicking a row
// in TasksView, like Projects/People). Its focus is the **Time Log**: every TaskTimeEntry logged against the
// task, each clickable to jump to the diary day where it lives (WorkspaceModel.revealTimeEntry). Full
// metadata editing stays in the proven TaskEditorSheet (a task has far more fields than Project/Person).
struct TaskDetailView: View {
    @Bindable var task: Task
    var asSheet: Bool = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(WorkspaceModel.self) private var workspace
    @State private var mailService = MailScriptService()

    // Whole-store queries feed the canonical ledger so a focus block's NET (capacity − other in-block
    // activity) is accurate — the same figure as the Tasks Time column and the Timesheet.
    @Query(sort: \Task.createdAt) private var allTasks: [Task]
    @Query private var allFocusBlocks: [FocusBlock]
    @Query private var allConversations: [EmailConversation]
    @Query private var allMeetings: [Minutes]
    @Query(sort: \Project.name) private var allProjects: [Project]
    @Query(sort: \Person.name) private var allPeople: [Person]

    @State private var subtreeCollapsedIds: Set<UUID> = []
    @State private var tagsText: String = ""
    @State private var repeatsText: String = ""
    @FocusState private var focusedSubtaskId: UUID?
    @State private var showingAddTime = false

    // One log with both time entries and the focus blocks this task backs, newest first.
    private enum LogItem: Identifiable {
        case entry(TaskTimeEntry)
        case block(FocusBlock)
        var id: UUID { switch self { case .entry(let e): e.id; case .block(let b): b.id } }
        var date: Date {
            switch self {
            case .entry(let e): e.date
            case .block(let b): b.dayRecord?.date ?? .distantPast
            }
        }
    }
    private var logItems: [LogItem] {
        (task.timeEntries.map(LogItem.entry) + task.focusBlocks.map(LogItem.block))
            .sorted { $0.date > $1.date }
    }

    private var blockNet: [UUID: Double] {
        TimeLedgerProjection.blockNet(focusBlocks: allFocusBlocks, tasks: allTasks,
                                      conversations: allConversations, meetings: allMeetings)
    }
    private func netHours(for block: FocusBlock) -> Double { blockNet[block.id] ?? 0 }

    private var totalHours: Double {
        TaskTimeReport.totalHours(entryHours: task.loggedHoursNormalized,
                                  hasEntries: !task.timeEntries.isEmpty,
                                  legacyHours: task.duration?.hoursNormalized,
                                  blockNets: task.focusBlocks.map(netHours(for:)))
    }

    var body: some View {
        // The model can be deleted while this view is still mounted (its tab is closed, but
        // the view renders once more in the same pass; a sheet is not a tab at all). Reading a
        // deleted model's stored properties traps, so bail out before the content is built.
        if task.isDeletedOrDetached {
            DeletedEntityPlaceholder(noun: "task")
        } else if asSheet {
            NavigationStack { coreContent }
            #if os(macOS)
            .frame(minWidth: 480, minHeight: 480)
            #endif
        } else {
            coreContent
        }
    }

    private var coreContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 4)
            DayActionBar(items: actionItems)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    section("Time Log (\(logItems.count))") { timeLogContent }
                    section("Subtasks (\(task.children.count))") { subtasksContent }
                }
                .padding(.bottom, 28)
            }
        }
        .background(AppTheme.background)
        .navigationTitle(task.summary)
        .toolbar {
            if asSheet {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .onAppear {
            tagsText = task.tags.joined(separator: ", ")
            repeatsText = task.recurrenceRule ?? ""
        }
        .sheet(isPresented: $showingAddTime) { LogTimeSheet(presetTask: task, presetDate: Date()) }
    }

    private var actionItems: [DayActionItem] {
        [
            DayActionItem(id: "addTime", systemName: "clock.badge.plus", color: AppTheme.duration,
                          tooltip: "Add time entry") { showingAddTime = true },
        ]
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(task.summary.isEmpty ? "Untitled task" : task.summary)
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.text)
            metadataCard
            chipRow
        }
    }

    // Inline-editable metadata, mirroring ProjectDetailView / PersonDetailView: every field binds
    // straight to the model, so there is no pencil-then-edit step.
    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            metaRow("Summary") {
                TextField("Summary", text: summaryBinding)
                    .textFieldStyle(.roundedBorder)
            }
            metaRow("Status") {
                TaskStatusMenu(task: task) { statusLabel }
            }
            metaRow("Project") {
                FuzzyPickerField(
                    allItems: allProjects,
                    selectedItem: projectBinding,
                    label: { $0.name },
                    chipColor: AppTheme.project,
                    onCreateItem: { makeProject($0) },
                    tapArea: true,
                    emptyLabel: "None — tap to choose or add"
                )
            }
            metaRow("Assignee") {
                FuzzyPickerField(
                    allItems: allPeople,
                    selectedItem: assigneeBinding,
                    label: { $0.name },
                    chipColor: AppTheme.person,
                    onCreateItem: { makePerson($0) },
                    tapArea: true,
                    emptyLabel: "Unassigned — tap to choose or add"
                )
            }
            metaRow("Priority") {
                Picker("", selection: priorityBinding) {
                    ForEach(TaskPriority.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 260)
            }
            metaRow("Due") { optionalDatePicker(dueBinding) }
            metaRow("Scheduled") { optionalDatePicker(scheduledBinding) }
            metaRow("Tags") {
                TextField("Comma-separated tags", text: $tagsText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: tagsText) { _, newValue in
                        task.tags = newValue.split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        task.updatedAt = Date()
                    }
            }
            metaRow("Notes", alignment: .top) {
                TextField("Notes", text: notesBinding, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...6)
            }
            metaRow("Blocked by", alignment: .top) {
                FuzzyPickerField(
                    allItems: blockerCandidates,
                    selected: blockersBinding,
                    label: \.summary,
                    chipColor: AppTheme.destructive,
                    tapArea: true,
                    emptyLabel: "None — tap to add prerequisite tasks"
                )
            }
            if !task.blocking.isEmpty {
                // Read-only: the inverse side, i.e. what is waiting on this task.
                metaRow("Blocking", alignment: .top) {
                    FlowLayout(spacing: 6) {
                        ForEach(task.blocking) { blocked in
                            Chip(label: blocked.summary,
                                 color: blocked.isOpen ? AppTheme.destructive : AppTheme.mutedText)
                        }
                    }
                }
            }
            metaRow("Repeats") {
                TextField("e.g. 1w, 2mo (blank = none)", text: $repeatsText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                    .onChange(of: repeatsText) { _, newValue in
                        task.recurrenceRule = RecurrenceRule.parse(newValue)?.normalized
                        touch()
                    }
            }
            metaRow("Wait until") { optionalDatePicker(waitBinding) }
            metaRow("Until") { optionalDatePicker(untilBinding) }
        }
        .padding(10)
        .background(AppTheme.cardRaised.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    // Read-only context that has no business being an editable field. The logged total is not here —
    // it is reported in the Time Log section, next to the entries it sums.
    @ViewBuilder private var chipRow: some View {
        if let source = task.source {
            Button { openSource(source) } label: {
                HStack(spacing: 3) {
                    Image(systemName: source.kind.systemImage).font(.caption2)
                    Text(source.title ?? source.url ?? source.kind.displayName).lineLimit(1)
                }
                .font(.caption)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(AppTheme.chipBackground(AppTheme.accent), in: Capsule())
                .foregroundStyle(AppTheme.accent)
            }
            .buttonStyle(.plain)
            .help("Open source")
        }
    }

    private func metaRow<Content: View>(_ label: String,
                                        alignment: VerticalAlignment = .firstTextBaseline,
                                        @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: alignment, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    /// Date field that can be cleared — a toggle plus a picker, matching TaskEditorSheet's semantics.
    @ViewBuilder private func optionalDatePicker(_ binding: Binding<Date?>) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { binding.wrappedValue != nil },
                                     set: { binding.wrappedValue = $0 ? (binding.wrappedValue ?? Date()) : nil }))
                .labelsHidden()
            if binding.wrappedValue != nil {
                DatePicker("", selection: Binding(get: { binding.wrappedValue ?? Date() },
                                                  set: { binding.wrappedValue = $0 }),
                           displayedComponents: .date)
                    .labelsHidden()
            } else {
                Text("Not set").font(.caption).foregroundStyle(AppTheme.mutedText)
            }
        }
    }

    // MARK: - Bindings (each stamps updatedAt, like the Person/Project pages)

    private func touch() { task.updatedAt = Date() }

    private var blockersBinding: Binding<[Task]> {
        Binding(get: { task.dependsOn }, set: { task.dependsOn = $0; touch() })
    }
    private var waitBinding: Binding<Date?> {
        Binding(get: { task.waitUntil }, set: { task.waitUntil = $0; touch() })
    }
    private var untilBinding: Binding<Date?> {
        Binding(get: { task.until }, set: { task.until = $0; touch() })
    }

    /// Any other task that wouldn't create a dependency cycle (same guard as the editor sheet).
    private var blockerCandidates: [Task] {
        let graph = Dictionary(uniqueKeysWithValues: allTasks.map { ($0.id, $0.dependsOn.map(\.id)) })
        return allTasks.filter { cand in
            guard cand.id != task.id else { return false }
            return !TaskDependency.wouldCreateCycle(taskID: task.id, newBlockerID: cand.id, dependsOn: graph)
        }
    }

    /// The unsaved breakdown outline is stored on the workspace tab, not in this view: the tab's content
    /// is torn down and rebuilt when you switch tabs, which would otherwise discard whatever was typed.
    private var breakdownDraft: Binding<String> {
        Binding(get: { workspace.active.breakdownDrafts[task.id] ?? "" },
                set: { workspace.active.breakdownDrafts[task.id] = $0 })
    }

    private var summaryBinding: Binding<String> {
        Binding(get: { task.summary }, set: { task.summary = $0; touch() })
    }
    private var notesBinding: Binding<String> {
        Binding(get: { task.notes ?? "" }, set: { task.notes = $0.isEmpty ? nil : $0; touch() })
    }
    private var projectBinding: Binding<Project?> {
        Binding(get: { task.project }, set: { task.project = $0; touch() })
    }
    private var assigneeBinding: Binding<Person?> {
        Binding(get: { task.assignee }, set: { task.assignee = $0; touch() })
    }
    private var priorityBinding: Binding<TaskPriority> {
        Binding(get: { task.priority }, set: { task.priorityRaw = $0.rawValue; touch() })
    }
    private var dueBinding: Binding<Date?> {
        Binding(get: { task.dueAt }, set: { task.dueAt = $0; touch() })
    }
    private var scheduledBinding: Binding<Date?> {
        Binding(get: { task.scheduledAt }, set: { task.scheduledAt = $0; touch() })
    }

    private func makeProject(_ name: String) -> Project? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let p = Project(name: trimmed)
        modelContext.insert(p)
        return p
    }

    private func makePerson(_ name: String) -> Person? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let p = Person(name: trimmed)
        modelContext.insert(p)
        return p
    }

    // Open where the task came from: email → Mail (via AppleScript); otherwise the deep link (slack://, https://).
    private func openSource(_ source: TaskSource) {
        if source.kind == .email, let email = source.email ?? task.originEmail {
            mailService.openMessage(email) { _ in }
            return
        }
        if let s = source.url, let url = URL(string: s) { openURL(url) }
    }

    private var statusLabel: some View {
        let (icon, color, text): (String, Color, String) = {
            switch task.status {
            case .todo:            ("circle", AppTheme.mutedText, "To do")
            case .started:         ("play.circle.fill", AppTheme.today, "Started")
            case .completed:       ("checkmark.circle.fill", AppTheme.completed, "Completed")
            case .cancelled:       ("xmark.circle.fill", AppTheme.mutedText, "Cancelled")
            case .followUpPending: ("clock.fill", AppTheme.followUp, "Follow up")
            }
        }()
        return HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(color)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(AppTheme.chipBackground(color), in: Capsule())
    }

    // MARK: - Sections

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        DaySectionHeader(title: title)
        VStack(alignment: .leading, spacing: 4) { content() }
            .padding(.horizontal)
    }

    @ViewBuilder private var timeLogContent: some View {
        if logItems.isEmpty {
            Text("No time logged against this task.")
                .foregroundStyle(AppTheme.mutedText).font(.callout).padding(.vertical, 2)
        } else {
            ForEach(logItems) { item in
                switch item {
                case .entry(let entry): logRow(entry: entry)
                case .block(let block): logRow(block: block)
                }
            }
            Divider().padding(.vertical, 2)
            HStack {
                Text("Total")
                    .font(AppTheme.bodyFont(size: 13).weight(.semibold))
                    .foregroundStyle(AppTheme.text)
                Spacer()
                Text(TimeFormat.hours(totalHours))
                    .font(AppTheme.bodyFont(size: 13).weight(.semibold))
                    .foregroundStyle(AppTheme.duration)
                    .monospacedDigit()
            }
            .padding(.trailing, 2)
        }
    }

    // A logged time entry → jumps to the diary day where it sits inside its block.
    private func logRow(entry: TaskTimeEntry) -> some View {
        logRow(icon: "clock", date: entry.date, hours: entry.duration.displayString,
               detail: entry.comment) { workspace.revealTimeEntry(entry) }
    }

    // A focus block backing this task → shows its dynamic NET hours; jumps to the block in the diary.
    private func logRow(block: FocusBlock) -> some View {
        let detail = [block.slot.displayName, block.comment].compactMap { $0 }
            .filter { !$0.isEmpty }.joined(separator: " · ")
        return logRow(icon: "square.stack", date: block.dayRecord?.date ?? block.createdAt,
                      hours: Duration(value: netHours(for: block), unit: .h).displayString,
                      detail: detail.isEmpty ? nil : detail) { workspace.revealFocusBlock(block) }
    }

    private func logRow(icon: String, date: Date, hours: String, detail: String?,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(AppTheme.duration).font(.system(size: 12))
                    .frame(width: 18).padding(.top, 2)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()))
                            .foregroundStyle(AppTheme.text)
                        Chip(label: hours, color: AppTheme.duration)
                    }
                    if let detail, !detail.isEmpty {
                        Text(detail).font(.caption).foregroundStyle(AppTheme.mutedText).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right.circle")
                    .foregroundStyle(AppTheme.mutedText).font(.system(size: 12)).padding(.top, 2)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Go to this in the diary")
    }

    // TaskSubtreeView supplies the row controls (drag-reorder, drag-onto-a-row to indent, "Detach from
    // Parent" to outdent); TaskBreakdownField supplies the batch outline entry. Together they are the
    // hybrid breakdown workflow.
    @ViewBuilder private var subtasksContent: some View {
        if task.children.isEmpty {
            Text("No subtasks yet.")
                .font(AppTheme.bodyFont(size: 12))
                .foregroundStyle(AppTheme.mutedText)
                .padding(.horizontal)
                .padding(.bottom, 2)
        } else {
            TaskSubtreeView(
                tasks: task.children,
                collapsedIds: $subtreeCollapsedIds,
                focusedId: $focusedSubtaskId,
                onEdit: { workspace.focusOrOpen(.task($0.persistentModelID)) },
                onMakeSubtask: { dragged, target in dragged.parent = target },
                onPromote: { [task] child in child.parent = task },
                onDelete: { modelContext.delete($0) }
            )
        }
        TaskBreakdownField(parent: task, text: breakdownDraft)
    }
}
