import SwiftUI
import SwiftData

struct TaskEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let task: Task?
    let defaultDate: Date
    var onTaskCreated: ((Task) -> Void)? = nil

    @Query(sort: \Project.name) private var projects: [Project]
    @Query(sort: \Person.name) private var people: [Person]

    @State private var summary = ""
    @State private var notes = ""
    @State private var selectedProject: Project?
    @State private var selectedAssignee: Person?
    @State private var scheduledDate: Date?
    @State private var tagsText = ""
    @State private var showingLogTime = false
    @State private var showingDeleteConfirm = false

    private var isNew: Bool { task == nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    summarySection
                    projectSection
                    assigneeSection
                    tagsSection
                    scheduleSection
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
                    Button(isNew ? "Add" : "Save") { save() }
                        .disabled(summary.trimmingCharacters(in: .whitespaces).isEmpty)
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
                selectedAssignee = people.first(where: { $0.name == "Greg Poole" })
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
        return GroupBox("Assignee") {
            FuzzyPickerField(
                allItems: people,
                selectedItem: $selectedAssignee,
                label: { $0.name },
                chipColor: AppTheme.person,
                tapArea: true,
                emptyLabel: "None — tap to assign",
                filters: filters.isEmpty ? nil : filters,
                defaultFilterId: defaultId
            )
        }
    }

    private var tagsSection: some View {
        GroupBox("Tags") {
            TextField("Comma-separated tags", text: $tagsText)
                .textFieldStyle(.plain)
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
        tagsText = t.tags.joined(separator: ", ")
    }

    private func deleteTask() {
        guard let t = task else { return }
        modelContext.delete(t)
        dismiss()
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
            t.project = selectedProject
            t.assignee = selectedAssignee
            t.tags = tags
            t.updatedAt = Date()
        } else {
            let newTask = Task(summary: trimmedSummary)
            newTask.notes = notes.isEmpty ? nil : notes
            newTask.scheduledAt = scheduledDate
            newTask.project = selectedProject
            newTask.assignee = selectedAssignee
            newTask.tags = tags
            modelContext.insert(newTask)
            onTaskCreated?(newTask)
        }
        dismiss()
    }
}
