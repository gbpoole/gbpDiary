import SwiftUI
import SwiftData

private enum FocusSource: String, CaseIterable {
    case task = "Task"
    case project = "Project"
}

struct FocusBlockEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var dayRecord: DayRecord
    var existingBlock: FocusBlock? = nil

    @Query(sort: \Task.summary) private var allTasks: [Task]
    @Query(sort: \Project.name) private var allProjects: [Project]

    @State private var source: FocusSource = .task
    @State private var selectedTask: Task?
    @State private var selectedProject: Project?
    @State private var durationText = ""
    @State private var durationError = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Source") {
                    Picker("Type", selection: $source) {
                        ForEach(FocusSource.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if source == .task {
                        Picker("Task", selection: $selectedTask) {
                            Text("None").tag(Optional<Task>.none)
                            ForEach(activeTasks) { t in
                                Text(t.summary).tag(Optional(t))
                            }
                        }
                    } else {
                        Picker("Project", selection: $selectedProject) {
                            Text("None").tag(Optional<Project>.none)
                            ForEach(allProjects) { p in
                                Text(p.name).tag(Optional(p))
                            }
                        }
                    }
                }

                Section("Duration") {
                    HStack {
                        TextField("e.g. 1.5h, 2d", text: $durationText)
                            .onChange(of: durationText) { _, _ in durationError = false }
                        if durationError {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                    Text("Units: h (hours), d (days ≈7.6h)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(existingBlock == nil ? "Add Focus Block" : "Edit Focus Block")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existingBlock == nil ? "Add" : "Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
        .onAppear { loadExisting() }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 280)
        #endif
    }

    private var activeTasks: [Task] {
        allTasks.filter { $0.status == .todo || $0.status == .started }
    }

    private var canSave: Bool {
        let hasSource = source == .task ? selectedTask != nil : selectedProject != nil
        return hasSource && Duration.parse(durationText) != nil
    }

    private func loadExisting() {
        guard let block = existingBlock else { return }
        durationText = block.duration.displayString
        if let t = block.task {
            source = .task
            selectedTask = t
        } else if let p = block.project {
            source = .project
            selectedProject = p
        }
    }

    private func save() {
        guard let duration = Duration.parse(durationText) else {
            durationError = true
            return
        }

        let block: FocusBlock
        if let existing = existingBlock {
            block = existing
        } else {
            let nextOrder = (dayRecord.focusBlocks.map(\.sortOrder).max() ?? -1) + 1
            block = FocusBlock(duration: duration, sortOrder: nextOrder)
            block.dayRecord = dayRecord
            modelContext.insert(block)
        }

        block.duration = duration
        if source == .task {
            block.task = selectedTask
            block.project = nil
        } else {
            block.project = selectedProject
            block.task = nil
        }

        dismiss()
    }
}
