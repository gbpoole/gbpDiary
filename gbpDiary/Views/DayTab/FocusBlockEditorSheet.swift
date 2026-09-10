import SwiftUI
import SwiftData

struct FocusBlockEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var dayRecord: DayRecord
    var existingBlock: FocusBlock? = nil

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
            if slot == .evening { return true }  // additive — an evening block coexists with any standard structure
            if slot == .allDay && hasHalfDay { return false }
            if (slot == .morning || slot == .afternoon) && hasAllDay { return false }
            return true
        }
    }

    @State private var selectedSlot: DaySlot = .allDay
    @State private var selectedTask: Task?
    @State private var eveningStart: Date = Date()
    @State private var comment = ""
    @State private var showingDeleteConfirm = false

    private func defaultEveningStart() -> Date {
        Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: dayRecord.date) ?? dayRecord.date
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    slotSection
                    // Evening blocks are pure overtime containers — no task source. Time is only ever
                    // assigned to tasks, so every standard block is task-backed.
                    if selectedSlot != .evening {
                        taskSection
                    }
                    commentSection
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

    private var taskSection: some View {
        GroupBox("Task") {
            FocusBlockTaskPickerRow(selectedTask: $selectedTask)
        }
    }

    private var commentSection: some View {
        GroupBox("Comment") {
            TextField("Optional note", text: $comment)
                .textFieldStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var slotSection: some View {
        GroupBox("Time Slot") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    ForEach(availableSlots, id: \.self) { s in
                        capsule(label: s.displayName, isActive: selectedSlot == s) { selectedSlot = s }
                    }
                }
                if selectedSlot == .evening {
                    HStack(spacing: 8) {
                        Text("Starts").font(.caption).foregroundStyle(.secondary)
                        DatePicker("", selection: $eveningStart, displayedComponents: [.hourAndMinute])
                            .labelsHidden()
                        Text("· overtime").font(.caption).foregroundStyle(.tertiary)
                    }
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
        if selectedSlot == .evening { return true }   // container — no task required
        return selectedTask != nil
    }

    private func loadExisting() {
        eveningStart = defaultEveningStart()
        guard let block = existingBlock else {
            if let first = availableSlots.first { selectedSlot = first }
            return
        }
        selectedSlot = block.slot
        comment = block.comment ?? ""
        if let start = block.startTime { eveningStart = start }
        // Legacy project-backed blocks load with no task selected (the launch migration normally converts
        // them first); saving re-backs the block with the chosen task.
        selectedTask = block.task
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
        block.comment = comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : comment
        block.startTime = selectedSlot == .evening ? eveningStart : nil
        // Time is only ever assigned to tasks; `project` is cleared on every save (legacy field).
        block.task = selectedSlot == .evening ? nil : selectedTask
        block.project = nil

        dismiss()
    }
}

// Isolated so @Query task changes don't force a re-render of the whole sheet.
private struct FocusBlockTaskPickerRow: View {
    @Environment(\.modelContext) private var modelContext
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
            onCreateItem: { makeTask($0) },
            tapArea: true,
            emptyLabel: "None — tap to select task"
        )
    }

    // Create a new Task on the fly while selecting one (auto-selected).
    private func makeTask(_ summary: String) -> Task? {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let task = Task(summary: trimmed)
        modelContext.insert(task)
        return task
    }
}
