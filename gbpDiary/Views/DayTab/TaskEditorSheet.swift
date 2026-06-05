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
    @State private var status: TaskStatus = .todo
    @State private var durationText = ""
    @State private var durationError = false
    @State private var selectedProject: Project?
    @State private var selectedAssignee: Person?
    @State private var scheduledDate: Date?
    @State private var followUpDate: Date?
    @State private var tagsText = ""

    private var isNew: Bool { task == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Summary", text: $summary)
                    ZStack(alignment: .topLeading) {
                        if notes.isEmpty {
                            Text("Notes (optional)")
                                .foregroundStyle(.tertiary)
                                .allowsHitTesting(false)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                        }
                        TextEditor(text: $notes)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 72)
                    }
                    .padding(4)
                    .background(.background, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                }

                Section("Status") {
                    Picker("Status", selection: $status) {
                        Text("To Do").tag(TaskStatus.todo)
                        Text("Started").tag(TaskStatus.started)
                        Text("Completed").tag(TaskStatus.completed)
                        Text("Follow-up Pending").tag(TaskStatus.followUpPending)
                        Text("Cancelled").tag(TaskStatus.cancelled)
                    }
                    if status == .followUpPending {
                        DatePicker("Follow-up date",
                                   selection: Binding(
                                       get: { followUpDate ?? Date() },
                                       set: { followUpDate = $0 }
                                   ),
                                   displayedComponents: .date)
                    }
                }

                Section("Scheduling") {
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

                Section("Duration") {
                    HStack {
                        TextField("e.g. 1.5h, 2d, 1w", text: $durationText)
                            .onChange(of: durationText) { _, _ in durationError = false }
                        if durationError {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                    Text("Units: h (hours), d (days ≈7.6h), w (weeks ≈38h)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Links") {
                    Picker("Project", selection: $selectedProject) {
                        Text("None").tag(Optional<Project>.none)
                        ForEach(projects) { p in
                            Text(p.name).tag(Optional(p))
                        }
                    }
                    Picker("Assignee", selection: $selectedAssignee) {
                        Text("None").tag(Optional<Person>.none)
                        ForEach(people) { p in
                            Text(p.name).tag(Optional(p))
                        }
                    }
                }

                Section("Tags") {
                    TextField("Comma-separated tags", text: $tagsText)
                }
            }
            .navigationTitle(isNew ? "New Task" : "Edit Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save") { save() }
                        .disabled(summary.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            if task != nil {
                populateFromTask()
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 520)
        #endif
    }

    private func populateFromTask() {
        guard let t = task else { return }
        summary = t.summary
        notes = t.notes ?? ""
        status = t.status
        selectedProject = t.project
        selectedAssignee = t.assignee
        scheduledDate = t.scheduledAt
        followUpDate = t.followUpAt
        tagsText = t.tags.joined(separator: ", ")
        durationText = t.duration?.displayString ?? ""
    }

    private func save() {
        let trimmedSummary = summary.trimmingCharacters(in: .whitespaces)
        guard !trimmedSummary.isEmpty else { return }

        var parsedDuration: Duration?
        if !durationText.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let d = Duration.parse(durationText) else {
                durationError = true
                return
            }
            parsedDuration = d
        }

        let tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if let t = task {
            t.summary = trimmedSummary
            t.notes = notes.isEmpty ? nil : notes
            t.status = status
            t.duration = parsedDuration
            t.scheduledAt = scheduledDate
            t.followUpAt = (status == .followUpPending) ? followUpDate : nil
            t.project = selectedProject
            t.assignee = selectedAssignee
            t.tags = tags
            t.updatedAt = Date()
        } else {
            let newTask = Task(summary: trimmedSummary)
            newTask.notes = notes.isEmpty ? nil : notes
            newTask.status = status
            newTask.duration = parsedDuration
            newTask.scheduledAt = scheduledDate
            newTask.followUpAt = (status == .followUpPending) ? followUpDate : nil
            newTask.project = selectedProject
            newTask.assignee = selectedAssignee
            newTask.tags = tags
            modelContext.insert(newTask)
            onTaskCreated?(newTask)
        }
        dismiss()
    }
}
