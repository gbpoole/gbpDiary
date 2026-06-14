import SwiftUI
import SwiftData

struct LogTimeSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var presetTask: Task? = nil
    var presetFocusBlock: FocusBlock? = nil
    var presetDate: Date = Date()
    // When set, the sheet edits the existing entry rather than creating a new one.
    var existingEntry: TaskTimeEntry? = nil

    @State private var selectedTask: Task?
    @State private var durationText = ""
    @State private var durationError = false
    @State private var comment = ""
    @State private var showingDeleteConfirm = false

    private var isEditing: Bool { existingEntry != nil }
    private var effectiveTask: Task? { existingEntry?.task ?? presetTask ?? selectedTask }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    if let task = effectiveTask, isEditing || presetTask != nil {
                        Text(task.summary)
                            .foregroundStyle(.secondary)
                    } else {
                        TaskPickerRow(selectedTask: $selectedTask)
                    }
                }

                Section("Time") {
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

                Section("Comment") {
                    TextField("Optional note", text: $comment)
                }

            }
            .navigationTitle(isEditing ? "Edit Activity" : "Log Time")
            .toolbar {
                if isEditing {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Delete") { showingDeleteConfirm = true }
                            .foregroundStyle(.red)
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
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let entry = existingEntry { modelContext.delete(entry) }
                    dismiss()
                }
            } message: {
                Text("This will permanently delete this activity entry.")
            }
        }
        .onAppear {
            if let entry = existingEntry {
                durationText = entry.duration.displayString
                comment = entry.comment ?? ""
            } else {
                selectedTask = presetTask
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
        #endif
    }

    private var canSave: Bool {
        effectiveTask != nil && Duration.parse(durationText) != nil
    }

    private func save() {
        guard let duration = Duration.parse(durationText) else {
            durationError = true
            return
        }

        if let entry = existingEntry {
            entry.duration = duration
            entry.comment = comment.isEmpty ? nil : comment
        } else {
            guard let task = effectiveTask else { return }
            let nextOrder = (task.timeEntries.map(\.sortOrder).max() ?? -1) + 1
            let entry = TaskTimeEntry(
                date: presetDate,
                duration: duration,
                comment: comment.isEmpty ? nil : comment,
                sortOrder: nextOrder
            )
            entry.task = task
            entry.focusBlock = presetFocusBlock
            modelContext.insert(entry)
        }

        dismiss()
    }
}

// Isolated in its own struct so that @Query task changes don't re-render
// the LogTimeSheet's text fields (comment, duration) while the user types.
private struct TaskPickerRow: View {
    @Query(sort: \Task.summary) private var allTasks: [Task]
    @Binding var selectedTask: Task?

    var body: some View {
        Picker("Task", selection: $selectedTask) {
            Text("None").tag(Optional<Task>.none)
            ForEach(allTasks) { t in
                Text(t.summary).tag(Optional(t))
            }
        }
    }
}
