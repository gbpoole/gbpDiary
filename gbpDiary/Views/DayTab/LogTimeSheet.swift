import SwiftUI
import SwiftData

struct LogTimeSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var presetTask: Task? = nil
    var presetFocusBlock: FocusBlock? = nil
    var presetDate: Date = Date()
    /// Blocks available for selection when there is no presetFocusBlock.
    /// Pass the day's focus blocks from ActivitySection; leave empty elsewhere.
    var availableFocusBlocks: [FocusBlock] = []
    // When set, the sheet edits the existing entry rather than creating a new one.
    var existingEntry: TaskTimeEntry? = nil

    @State private var selectedTask: Task?
    @State private var selectedFocusBlock: FocusBlock?
    @State private var entryDate: Date = Date()
    @State private var durationText = ""
    @State private var durationError = false
    @State private var comment = ""
    @State private var showingDeleteConfirm = false

    private var isEditing: Bool { existingEntry != nil }
    private var effectiveTask: Task? { existingEntry?.task ?? presetTask ?? selectedTask }

    /// Show the focus block selector when creating a new entry and blocks are available
    /// to choose from (i.e. no block was pre-selected by the caller).
    private var showFocusBlockSelector: Bool {
        !isEditing && presetFocusBlock == nil && !availableFocusBlocks.isEmpty
    }

    private struct DurationPreset: Identifiable {
        let id: String
        let label: String
        let value: String   // parseable string set into durationText
        let hours: Double
    }
    private let durationPresets: [DurationPreset] = [
        DurationPreset(id: "15m",  label: "15m",  value: "0.25h", hours: 0.25),
        DurationPreset(id: "30m",  label: "30m",  value: "0.5h",  hours: 0.5),
        DurationPreset(id: "1h",   label: "1h",   value: "1h",    hours: 1.0),
        DurationPreset(id: "1.5h", label: "1.5h", value: "1.5h",  hours: 1.5),
        DurationPreset(id: "2h",   label: "2h",   value: "2h",    hours: 2.0),
        DurationPreset(id: "3h",   label: "3h",   value: "3h",    hours: 3.0),
    ]
    private func isPresetActive(_ preset: DurationPreset) -> Bool {
        guard let d = Duration.parse(durationText.trimmingCharacters(in: .whitespaces)) else { return false }
        return abs(d.hoursNormalized - preset.hours) < 0.01
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    taskSection
                    dateSection
                    if showFocusBlockSelector { focusBlockSection }
                    durationSection
                    commentSection
                }
                .padding()
            }
            .navigationTitle(isEditing ? "Edit Activity" : "Log Time")
            .toolbar {
                if isEditing {
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
                    Button(isEditing ? "Save" : "Add") { save() }
                        .disabled(!canSave)
                }
            }
            .alert("Delete Activity?", isPresented: $showingDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    if let entry = existingEntry { modelContext.delete(entry) }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete this activity entry.")
            }
        }
        .onAppear {
            if let entry = existingEntry {
                durationText = entry.duration.displayString
                comment = entry.comment ?? ""
                entryDate = entry.date
            } else {
                selectedTask = presetTask
                entryDate = currentTimeOn(presetDate)
                selectedFocusBlock = blockMatching(entryDate)
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
        #endif
    }

    // MARK: - Sections

    private var taskSection: some View {
        GroupBox("Task") {
            if let task = effectiveTask, isEditing || presetTask != nil {
                Text(task.summary)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TaskFuzzyPickerRow(selectedTask: $selectedTask)
            }
        }
    }

    private var dateSection: some View {
        GroupBox("Date & Time") {
            DatePicker("", selection: $entryDate, displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .onChange(of: entryDate) { _, newDate in
                    // Auto-update the block selection when time changes,
                    // but only if the user hasn't explicitly picked one.
                    selectedFocusBlock = blockMatching(newDate)
                }
        }
    }

    private var focusBlockSection: some View {
        GroupBox("Focus Block") {
            HStack(spacing: 6) {
                blockCapsule(block: nil, label: "None")
                ForEach(availableFocusBlocks.sorted(by: { $0.sortOrder < $1.sortOrder })) { block in
                    blockCapsule(block: block, label: blockLabel(block))
                }
            }
        }
    }

    private func blockCapsule(block: FocusBlock?, label: String) -> some View {
        let isActive = selectedFocusBlock?.id == block?.id
        return Button(label) { selectedFocusBlock = block }
            .buttonStyle(.plain)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isActive ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(isActive ? Color.white : Color.primary)
    }

    private func blockLabel(_ block: FocusBlock) -> String {
        let slot = block.slot.displayName
        let label = block.displayLabel
        return label == "Focus block" ? slot : "\(slot) · \(label)"
    }

    private var durationSection: some View {
        GroupBox("Duration") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(durationPresets) { preset in
                        Button(preset.label) {
                            durationText = preset.value
                            durationError = false
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isPresetActive(preset) ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
                        .foregroundStyle(isPresetActive(preset) ? Color.white : Color.primary)
                    }
                }
                HStack(spacing: 6) {
                    TextField("Custom (e.g. 2.5h)", text: $durationText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .onChange(of: durationText) { _, _ in durationError = false }
                    if durationError {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
        }
    }

    private var commentSection: some View {
        GroupBox("Comment") {
            TextField("Optional note", text: $comment)
                .textFieldStyle(.plain)
        }
    }

    // MARK: - Helpers

    private var canSave: Bool {
        effectiveTask != nil && Duration.parse(durationText) != nil
    }

    /// Returns the focus block whose slot best matches the given time.
    private func blockMatching(_ date: Date) -> FocusBlock? {
        guard !availableFocusBlocks.isEmpty else { return nil }
        if availableFocusBlocks.count == 1 { return availableFocusBlocks.first }
        let hour = Calendar.current.component(.hour, from: date)
        let targetSlot: DaySlot = hour < 12 ? .morning : .afternoon
        return availableFocusBlocks.first(where: { $0.slot == targetSlot })
            ?? availableFocusBlocks.first(where: { $0.slot == .allDay })
            ?? availableFocusBlocks.first
    }

    private func currentTimeOn(_ date: Date) -> Date {
        let cal = Calendar.current
        let now = Date()
        let h = cal.component(.hour, from: now)
        let m = cal.component(.minute, from: now)
        return cal.date(bySettingHour: h, minute: m, second: 0, of: date) ?? date
    }

    private func save() {
        guard let duration = Duration.parse(durationText) else {
            durationError = true
            return
        }

        if let entry = existingEntry {
            entry.date = entryDate
            entry.duration = duration
            entry.comment = comment.isEmpty ? nil : comment
        } else {
            guard let task = effectiveTask else { return }
            let nextOrder = (task.timeEntries.map(\.sortOrder).max() ?? -1) + 1
            let entry = TaskTimeEntry(
                date: entryDate,
                duration: duration,
                comment: comment.isEmpty ? nil : comment,
                sortOrder: nextOrder
            )
            entry.task = task
            entry.focusBlock = presetFocusBlock ?? selectedFocusBlock
            modelContext.insert(entry)
        }

        dismiss()
    }
}

// Isolated in its own struct so that @Query task changes don't re-render
// the LogTimeSheet's text fields (comment, duration) while the user types.
private struct TaskFuzzyPickerRow: View {
    @Query(sort: \Task.summary) private var allTasks: [Task]
    @Binding var selectedTask: Task?

    var body: some View {
        FuzzyPickerField(
            allItems: allTasks,
            selectedItem: $selectedTask,
            label: { $0.summary },
            chipColor: AppTheme.accent,
            tapArea: true,
            emptyLabel: "None — tap to select task"
        )
    }
}
