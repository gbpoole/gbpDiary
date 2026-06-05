import SwiftUI
import SwiftData

struct LogTimeSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var presetTask: Task? = nil
    var presetFocusBlock: FocusBlock? = nil
    var presetDate: Date = Date()

    @Query(sort: \Task.summary) private var allTasks: [Task]

    @State private var selectedTask: Task?
    @State private var date: Date = Date()
    @State private var durationText = ""
    @State private var durationError = false
    @State private var comment = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    if let task = presetTask {
                        Text(task.summary)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Task", selection: $selectedTask) {
                            Text("None").tag(Optional<Task>.none)
                            ForEach(allTasks) { t in
                                Text(t.summary).tag(Optional(t))
                            }
                        }
                    }
                }

                Section("Time") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
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
            .navigationTitle("Log Time")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(!canSave)
                }
            }
        }
        .onAppear {
            selectedTask = presetTask
            date = presetDate
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
        #endif
    }

    private var canSave: Bool {
        let task = presetTask ?? selectedTask
        return task != nil && Duration.parse(durationText) != nil
    }

    private func save() {
        guard let task = presetTask ?? selectedTask,
              let duration = Duration.parse(durationText) else { return }
        let nextOrder = (task.timeEntries.map(\.sortOrder).max() ?? -1) + 1
        let entry = TaskTimeEntry(
            date: date,
            duration: duration,
            comment: comment.isEmpty ? nil : comment,
            sortOrder: nextOrder
        )
        entry.task = task
        entry.focusBlock = presetFocusBlock
        modelContext.insert(entry)
        dismiss()
    }
}
