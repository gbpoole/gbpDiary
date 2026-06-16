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

    @Query(sort: \Project.name) private var allProjects: [Project]
    @Query(sort: \FocusBlock.sortOrder) private var allFocusBlocks: [FocusBlock]

    private var siblingsForDay: [FocusBlock] {
        allFocusBlocks.filter { $0.dayRecord?.id == dayRecord.id && $0.id != existingBlock?.id }
    }

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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sourceSection
                    if source == .task {
                        taskSection
                    } else {
                        projectSection
                    }
                    slotSection
                }
                .padding()
            }
            .navigationTitle(existingBlock == nil ? "Add Focus Block" : "Edit Focus Block")
            .toolbar {
                if existingBlock != nil {
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
        .frame(minWidth: 420, minHeight: 280)
        #endif
    }

    // MARK: - Sections

    private var sourceSection: some View {
        GroupBox("Source") {
            HStack(spacing: 6) {
                ForEach(FocusSource.allCases, id: \.self) { s in
                    capsule(label: s.rawValue, isActive: source == s) { source = s }
                }
            }
        }
    }

    private var taskSection: some View {
        GroupBox("Task") {
            FocusBlockTaskPickerRow(selectedTask: $selectedTask)
        }
    }

    private var projectSection: some View {
        GroupBox("Project") {
            FuzzyPickerField(
                allItems: allProjects,
                selectedItem: $selectedProject,
                label: { $0.name },
                chipColor: AppTheme.project,
                tapArea: true,
                emptyLabel: "None — tap to select project"
            )
        }
    }

    private var slotSection: some View {
        GroupBox("Time Slot") {
            HStack(spacing: 6) {
                ForEach(availableSlots, id: \.self) { s in
                    capsule(label: s.displayName, isActive: selectedSlot == s) { selectedSlot = s }
                }
            }
        }
    }

    private func capsule(label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(.plain)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isActive ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(isActive ? Color.white : Color.primary)
    }

    // MARK: - Helpers

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

// Isolated so @Query task changes don't force a re-render of the whole sheet.
private struct FocusBlockTaskPickerRow: View {
    @Query(sort: \Task.summary) private var allTasks: [Task]
    @Binding var selectedTask: Task?

    private var activeTasks: [Task] {
        allTasks.filter { $0.status == .todo || $0.status == .started }
    }

    var body: some View {
        FuzzyPickerField(
            allItems: activeTasks,
            selectedItem: $selectedTask,
            label: { $0.summary },
            chipColor: AppTheme.completed,
            tapArea: true,
            emptyLabel: "None — tap to select task"
        )
    }
}
