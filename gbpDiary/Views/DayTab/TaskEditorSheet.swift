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
    @State private var followUpEnabled = false
    @State private var followUpDate: Date?
    @State private var tagsText = ""
    @State private var showingLogTime = false
    @State private var deletingEntry: TaskTimeEntry?

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
                        Text("Cancelled").tag(TaskStatus.cancelled)
                    }
                }

                Section("Follow-up") {
                    Toggle("Has follow-up date", isOn: $followUpEnabled)
                        .onChange(of: followUpEnabled) { _, on in
                            if on && followUpDate == nil {
                                followUpDate = Calendar.current.date(byAdding: .day, value: 1,
                                    to: Calendar.current.startOfDay(for: .now))
                            }
                        }
                    if followUpEnabled {
                        DatePicker("Date",
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

                if let t = task {
                    timeLogSection(t)
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
        .sheet(isPresented: $showingLogTime) {
            if let t = task {
                LogTimeSheet(presetTask: t, presetDate: defaultDate)
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 520)
        #endif
    }

    @ViewBuilder
    private func timeLogSection(_ t: Task) -> some View {
        Section {
            let entries = t.timeEntries.sorted { $0.date > $1.date }
            if entries.isEmpty {
                Text("No time logged yet.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(entries) { entry in
                    HStack {
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
                        Spacer()
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            modelContext.delete(entry)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            modelContext.delete(entry)
                        }
                    }
                }
            }
            Button("Add Entry…") { showingLogTime = true }
        } header: {
            HStack {
                Text("Time Log")
                if let logged = t.loggedDuration {
                    Spacer()
                    Chip(label: logged.displayString, color: AppTheme.duration)
                }
            }
        }
    }

    private func populateFromTask() {
        guard let t = task else { return }
        summary = t.summary
        notes = t.notes ?? ""
        status = t.status == .followUpPending ? .completed : t.status
        selectedProject = t.project
        selectedAssignee = t.assignee
        scheduledDate = t.scheduledAt
        followUpEnabled = t.followUpAt != nil
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
            t.duration = parsedDuration
            t.scheduledAt = scheduledDate
            t.project = selectedProject
            t.assignee = selectedAssignee
            t.tags = tags
            t.updatedAt = Date()
            if followUpEnabled, let date = followUpDate {
                t.setFollowUp(date: date)
            } else {
                t.clearFollowUp()
                t.status = status
            }
        } else {
            let newTask = Task(summary: trimmedSummary)
            newTask.notes = notes.isEmpty ? nil : notes
            newTask.duration = parsedDuration
            newTask.scheduledAt = scheduledDate
            newTask.project = selectedProject
            newTask.assignee = selectedAssignee
            newTask.tags = tags
            modelContext.insert(newTask)
            if followUpEnabled, let date = followUpDate {
                newTask.setFollowUp(date: date)
            } else {
                newTask.status = status
            }
            onTaskCreated?(newTask)
        }
        dismiss()
    }
}
