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
    @Query(sort: \FocusBlock.sortOrder) private var allFocusBlocks: [FocusBlock]

    // Other blocks for this day (the current block, if editing, is excluded so its slot remains available).
    private var siblingsForDay: [FocusBlock] {
        allFocusBlocks.filter { $0.dayRecord?.id == dayRecord.id && $0.id != existingBlock?.id }
    }

    // Slots that can still be chosen: removes taken slots and enforces all-day ↔ half-day exclusivity.
    private var availableSlots: [DaySlot] {
        let taken = Set(siblingsForDay.map(\.slot))
        let hasAllDay  = taken.contains(.allDay)
        let hasHalfDay = taken.contains(.morning) || taken.contains(.afternoon)
        return DaySlot.allCases.filter { slot in
            guard !taken.contains(slot) else { return false }
            if slot == .allDay && hasHalfDay { return false }
            if (slot == .morning || slot == .afternoon) && hasAllDay { return false }
            return true
        }
    }

    @State private var source: FocusSource = .task
    @State private var selectedSlot: DaySlot = .allDay
    @State private var selectedTask: Task?
    @State private var selectedProject: Project?
    @State private var showingDeleteConfirm = false

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

                Section("Schedule") {
                    Picker("Time Slot", selection: $selectedSlot) {
                        ForEach(availableSlots, id: \.self) { s in
                            Text(s.displayName).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

            }
            .navigationTitle(existingBlock == nil ? "Add Focus Block" : "Edit Focus Block")
            .toolbar {
                if existingBlock != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Delete") { showingDeleteConfirm = true }
                            .foregroundStyle(.red)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existingBlock == nil ? "Add" : "Save") { save() }
                        .disabled(!canSave)
                }
            }
            .alert("Delete Focus Block?", isPresented: $showingDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let block = existingBlock { modelContext.delete(block) }
                    dismiss()
                }
            } message: {
                Text("This will permanently delete this focus block and unlink any logged activities.")
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
        source == .task ? selectedTask != nil : selectedProject != nil
    }

    private func loadExisting() {
        guard let block = existingBlock else {
            if let first = availableSlots.first { selectedSlot = first }
            return
        }
        selectedSlot = block.slot
        if let t = block.task {
            source = .task
            selectedTask = t
        } else if let p = block.project {
            source = .project
            selectedProject = p
        }
    }

    private func save() {
        let duration = selectedSlot.defaultDuration

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
        block.slot = selectedSlot
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
