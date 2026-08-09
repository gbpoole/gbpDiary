import SwiftUI
import SwiftData

struct TaskEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let task: Task?
    let defaultDate: Date
    var onTaskCreated: ((Task) -> Void)? = nil
    /// Meeting action-item presets: pre-select the project, link the new task to the meeting, and
    /// offer its attendees as one-tap assignees.
    var presetProject: Project? = nil
    var originMinutes: Minutes? = nil
    var attendees: [Person] = []
    /// When true (meeting action items), an assignee must be chosen before saving.
    var requireAssignee: Bool = false
    /// Pre-seed the summary/notes for a new task (e.g. from an email being turned into a todo).
    var presetSummary: String? = nil
    var presetNotes: String? = nil

    @Query(sort: \Project.name) private var projects: [Project]
    @Query(sort: \Person.name) private var people: [Person]
    @Query(sort: \Task.summary) private var allTasks: [Task]

    @State private var summary = ""
    @State private var notes = ""
    @State private var selectedProject: Project?
    @State private var selectedAssignee: Person?
    @State private var scheduledDate: Date?
    @State private var dueDate: Date?
    @State private var priority: TaskPriority = .none
    @State private var selectedBlockers: [Task] = []
    @State private var tagsText = ""
    @State private var showingLogTime = false
    @State private var showingDeleteConfirm = false
    @State private var mailService = MailScriptService()
    @State private var openEmailError: String?

    private var isNew: Bool { task == nil }

    private var canSave: Bool {
        !summary.trimmingCharacters(in: .whitespaces).isEmpty && (!requireAssignee || selectedAssignee != nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    summarySection
                    if let email = task?.originEmail { fromEmailSection(email) }
                    projectSection
                    assigneeSection
                    tagsSection
                    prioritySection
                    scheduleSection
                    dueSection
                    dependsSection
                    blockingSection
                    notesSection
                    if let t = task {
                        timeLogSection(t)
                    }
                }
                .padding()
            }
            .navigationTitle(isNew ? "New Task" : "Edit Task")
            .toolbar {
                if !isNew {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Delete") { showingDeleteConfirm = true }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save") { save() }.disabled(!canSave)
                }
            }
            .alert("Delete Task?", isPresented: $showingDeleteConfirm) {
                Button("Delete", role: .destructive) { deleteTask() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete the task.")
            }
        }
        .onAppear {
            if task != nil {
                populateFromTask()
            } else {
                // Default the assignee to the "Me" person configured in Settings (nil if unset).
                selectedAssignee = people.first(where: { $0.id == AppSettingsStore.myPersonID })
                selectedProject = presetProject
                if let s = presetSummary { summary = s }
                if let n = presetNotes { notes = n }
            }
        }
        .sheet(isPresented: $showingLogTime) {
            if let t = task {
                LogTimeSheet(presetTask: t, presetDate: defaultDate)
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 480)
        #endif
    }

    // MARK: - Sections

    private var summarySection: some View {
        GroupBox("Task") {
            TextField("Summary", text: $summary)
                .textFieldStyle(.plain)
        }
    }

    // Shown when the task was created from an email — links back to the source, openable in Mail.
    private func fromEmailSection(_ email: EmailMessage) -> some View {
        GroupBox("From email") {
            HStack(spacing: 8) {
                Image(systemName: email.direction == .sent ? "paperplane" : "envelope")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(email.fromName?.isEmpty == false ? email.fromName! : email.fromAddress)
                        .font(.callout).lineLimit(1)
                    Text(email.subject.isEmpty ? "(no subject)" : email.subject)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Button { openEmail(email) } label: { Label("Open in Mail", systemImage: "arrow.up.right.square") }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .alert("Couldn't open email", isPresented: Binding(get: { openEmailError != nil }, set: { if !$0 { openEmailError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(openEmailError ?? "") }
        }
    }

    private func openEmail(_ email: EmailMessage) {
        mailService.openMessage(email) { result in
            if case .failure(let error) = result { openEmailError = error.userMessage }
        }
    }

    private var notesSection: some View {
        GroupBox("Notes") {
            ZStack(alignment: .topLeading) {
                if notes.isEmpty {
                    Text("Optional notes…")
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                        .padding(.top, 2)
                }
                TextEditor(text: $notes)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 60)
            }
        }
    }

    private var projectSection: some View {
        GroupBox("Project") {
            FuzzyPickerField(
                allItems: projects,
                selectedItem: $selectedProject,
                label: { $0.name },
                chipColor: AppTheme.project,
                onCreateItem: { makeProject($0) },
                tapArea: true,
                emptyLabel: "None — tap to link project"
            )
        }
    }

    private var assigneeSection: some View {
        var filters: [PickerFilter<Person>] = []
        if let proj = selectedProject {
            filters.append(PickerFilter(
                id: "project:\(proj.id.uuidString)",
                label: proj.name,
                chipColor: AppTheme.project,
                group: "Project"
            ) { person in
                proj.devTeam.contains(where: { $0.id == person.id }) ||
                proj.sciTeam.contains(where: { $0.id == person.id })
            })
        }
        var seen = Set<String>()
        let instFilters: [PickerFilter<Person>] = people
            .compactMap(\.institution)
            .filter { seen.insert($0.id.uuidString).inserted }
            .sorted { $0.name < $1.name }
            .map { inst in
                PickerFilter(id: "inst:\(inst.id.uuidString)", label: inst.name, chipColor: AppTheme.institution, group: "Institution") {
                    $0.institution?.id == inst.id
                }
            }
        filters += instFilters
        let defaultId = selectedProject.map { "project:\($0.id.uuidString)" }

        // With an attendee list, the chips are the primary assignee control; the picker below is only
        // for assigning someone who isn't an attendee — so it stays empty (no duplicate green chip)
        // when the assignee is one of the attendees.
        let attendeeIDs = Set(attendees.map(\.id))
        let otherPeople = attendees.isEmpty ? people : people.filter { !attendeeIDs.contains($0.id) }
        let pickerBinding: Binding<Person?> = attendees.isEmpty ? $selectedAssignee : Binding(
            get: { selectedAssignee.flatMap { attendeeIDs.contains($0.id) ? nil : $0 } },
            set: { selectedAssignee = $0 }
        )
        return GroupBox("Assignee") {
            VStack(alignment: .leading, spacing: 8) {
                if !attendees.isEmpty {
                    // One-tap assign to a meeting attendee: neutral = off, green = the chosen assignee.
                    FlowLayout(spacing: 6) {
                        ForEach(attendees) { person in
                            let isOn = selectedAssignee?.id == person.id
                            Button { selectedAssignee = isOn ? nil : person } label: {
                                Chip(label: person.name, color: isOn ? AppTheme.person : AppTheme.mutedText)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                FuzzyPickerField(
                    allItems: otherPeople,
                    selectedItem: pickerBinding,
                    label: { $0.name },
                    chipColor: AppTheme.person,
                    onCreateItem: { makePerson($0) },
                    tapArea: true,
                    emptyLabel: attendees.isEmpty ? "None — tap to assign" : "Assign someone else…",
                    filters: filters.isEmpty ? nil : filters,
                    defaultFilterId: defaultId
                )
            }
        }
    }

    private var tagsSection: some View {
        GroupBox("Tags") {
            TextField("Comma-separated tags", text: $tagsText)
                .textFieldStyle(.plain)
        }
    }

    private var prioritySection: some View {
        GroupBox("Priority") {
            Picker("", selection: $priority) {
                ForEach(TaskPriority.allCases, id: \.self) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // Candidate blockers: any other task that wouldn't create a dependency cycle.
    private var blockerCandidates: [Task] {
        let graph = Dictionary(uniqueKeysWithValues: allTasks.map { ($0.id, $0.dependsOn.map(\.id)) })
        return allTasks.filter { cand in
            guard cand.id != task?.id else { return false }
            if let id = task?.id,
               TaskDependency.wouldCreateCycle(taskID: id, newBlockerID: cand.id, dependsOn: graph) {
                return false
            }
            return true
        }
    }

    private var dependsSection: some View {
        GroupBox("Blocked by") {
            FuzzyPickerField(
                allItems: blockerCandidates,
                selected: $selectedBlockers,
                label: \.summary,
                chipColor: AppTheme.destructive,
                tapArea: true,
                emptyLabel: "None — tap to add prerequisite tasks"
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // Read-only: the tasks that depend on this one (inverse of their "Blocked by").
    @ViewBuilder private var blockingSection: some View {
        if let t = task, !t.blocking.isEmpty {
            GroupBox("Blocking") {
                FlowLayout(spacing: 6) {
                    ForEach(t.blocking) { blocked in
                        Chip(label: blocked.summary,
                             color: blocked.isOpen ? AppTheme.destructive : AppTheme.mutedText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var dueSection: some View {
        GroupBox("Due") {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Has a due date", isOn: Binding(
                    get: { dueDate != nil },
                    set: { if $0 { dueDate = dueDate ?? defaultDate } else { dueDate = nil } }
                ))
                if dueDate != nil {
                    DatePicker("Date",
                               selection: Binding(get: { dueDate ?? defaultDate }, set: { dueDate = $0 }),
                               displayedComponents: .date)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var scheduleSection: some View {
        GroupBox("Schedule") {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Schedule for a day", isOn: Binding(
                    get: { scheduledDate != nil },
                    set: { if $0 { scheduledDate = defaultDate } else { scheduledDate = nil } }
                ))
                if scheduledDate != nil {
                    DatePicker("Date",
                               selection: Binding(
                                   get: { scheduledDate ?? defaultDate },
                                   set: { scheduledDate = $0 }
                               ),
                               displayedComponents: .date)
                }
            }
        }
    }

    @ViewBuilder
    private func timeLogSection(_ t: Task) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                let entries = t.timeEntries.sorted { $0.date > $1.date }
                if entries.isEmpty {
                    Text("No time logged yet.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .padding(.vertical, 2)
                } else {
                    ForEach(entries) { entry in
                        HStack(spacing: 6) {
                            Text(entry.date, format: .dateTime.month(.abbreviated).day())
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Chip(label: entry.duration.displayString, color: AppTheme.duration)
                            if let c = entry.comment {
                                Text(c)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Button {
                                modelContext.delete(entry)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                }
                Button("Add Entry…") { showingLogTime = true }
                    .font(.callout)
                    .foregroundStyle(AppTheme.accent)
                    .buttonStyle(.plain)
                    .padding(.top, 2)
            }
        } label: {
            HStack {
                Text("Time Log")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                if let logged = t.loggedDuration {
                    Chip(label: logged.displayString, color: AppTheme.duration)
                }
            }
        }
    }

    // MARK: - Helpers

    private func populateFromTask() {
        guard let t = task else { return }
        summary = t.summary
        notes = t.notes ?? ""
        selectedProject = t.project
        selectedAssignee = t.assignee
        scheduledDate = t.scheduledAt
        dueDate = t.dueAt
        priority = t.priority
        selectedBlockers = t.dependsOn
        tagsText = t.tags.joined(separator: ", ")
    }

    private func deleteTask() {
        guard let t = task else { return }
        modelContext.delete(t)
        dismiss()
    }

    // Create a new Project on the fly while linking one (auto-selected).
    private func makeProject(_ projectName: String) -> Project? {
        let trimmed = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let project = Project(name: trimmed)
        modelContext.insert(project)
        return project
    }

    // Create a new Person on the fly while assigning (auto-selected).
    private func makePerson(_ personName: String) -> Person? {
        let trimmed = personName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let person = Person(name: trimmed)
        modelContext.insert(person)
        return person
    }

    private func save() {
        let trimmedSummary = summary.trimmingCharacters(in: .whitespaces)
        guard !trimmedSummary.isEmpty else { return }

        let tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if let t = task {
            t.summary = trimmedSummary
            t.notes = notes.isEmpty ? nil : notes
            t.scheduledAt = scheduledDate
            t.dueAt = dueDate
            t.priorityRaw = priority.rawValue
            t.dependsOn = selectedBlockers
            t.project = selectedProject
            t.assignee = selectedAssignee
            t.tags = tags
            t.updatedAt = Date()
        } else {
            let newTask = Task(summary: trimmedSummary)
            newTask.notes = notes.isEmpty ? nil : notes
            newTask.scheduledAt = scheduledDate
            newTask.dueAt = dueDate
            newTask.priorityRaw = priority.rawValue
            newTask.dependsOn = selectedBlockers
            newTask.project = selectedProject
            newTask.assignee = selectedAssignee
            newTask.tags = tags
            if let origin = originMinutes {
                newTask.originMinutes = origin
                newTask.meetingTaskSortOrder = (origin.newTasks.map(\.meetingTaskSortOrder).max() ?? -1) + 1
            }
            modelContext.insert(newTask)
            onTaskCreated?(newTask)
        }
        dismiss()
    }
}
