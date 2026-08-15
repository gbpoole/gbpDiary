import SwiftUI
import SwiftData

struct LogTimeSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var presetTask: Task? = nil
    var presetDate: Date = Date()
    // When set, the entry logs time against a sent email (no task required).
    var presetEmail: EmailMessage? = nil
    // When set, the sheet edits the existing entry rather than creating a new one.
    var existingEntry: TaskTimeEntry? = nil

    @State private var selectedTask: Task?
    @State private var selectedProjectFilter: Project?
    @State private var isProjectPickerOpen = false
    @State private var entryDate: Date = Date()
    @State private var durationText = ""
    @State private var durationError = false
    @State private var comment = ""
    @State private var showingDeleteConfirm = false

    private var isEditing: Bool { existingEntry != nil }
    private var effectiveTask: Task? { existingEntry?.task ?? presetTask ?? selectedTask }

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
                    if let email = presetEmail ?? existingEntry?.email {
                        emailContextSection(email)
                    } else {
                        if !isEditing && presetTask == nil {
                            projectFilterSection
                        }
                        taskSection
                    }
                    commentSection
                    durationSection
                    timeSection
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
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save() }
                        .disabled(!canSave)
                        .keyboardShortcut(.defaultAction)
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
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
        #endif
    }

    // MARK: - Sections

    private var projectFilterSection: some View {
        GroupBox("Project") {
            ProjectFilterPickerRow(
                selectedProject: $selectedProjectFilter,
                isPresented: $isProjectPickerOpen,
                autoFocus: true
            )
        }
    }

    private var taskSection: some View {
        GroupBox("Task") {
            if let task = effectiveTask, isEditing || presetTask != nil {
                Text(task.summary)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TaskPickerRow(
                    selectedTask: $selectedTask,
                    projectFilter: selectedProjectFilter,
                    onChangeProject: { isProjectPickerOpen = true },
                    onClearProject: { selectedProjectFilter = nil }
                )
            }
        }
    }

    private var timeSection: some View {
        GroupBox("Time") {
            DatePicker("", selection: $entryDate, displayedComponents: [.hourAndMinute])
                .labelsHidden()
        }
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
        let hasTarget = effectiveTask != nil || presetEmail != nil || existingEntry?.email != nil
        return hasTarget && Duration.parse(durationText) != nil
    }

    private func emailContextSection(_ email: EmailMessage) -> some View {
        GroupBox("Email") {
            HStack(spacing: 6) {
                Image(systemName: "paperplane").foregroundStyle(.secondary)
                Text(email.subject.isEmpty ? "(no subject)" : email.subject).lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // The current time-of-day on the shown day — or the real weekend time when parked on the green
    // Monday (so weekend work books to Friday's overtime). See WeekendPolicy.logNowDate.
    private func currentTimeOn(_ date: Date) -> Date {
        WeekendPolicy.logNowDate(viewedDate: date)
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
            // Don't touch focusBlock here — the Activity section re-buckets by time when the time
            // changes. Reassigning here (without the day's blocks) would wrongly drop the entry.
        } else if let email = presetEmail {
            let nextOrder = (email.timeEntries.map(\.sortOrder).max() ?? -1) + 1
            let entry = TaskTimeEntry(date: entryDate, duration: duration,
                                      comment: comment.isEmpty ? nil : comment, sortOrder: nextOrder)
            entry.email = email
            modelContext.insert(entry)
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
            // Block membership is derived from the entry's time by the Activity section — not stored.
            modelContext.insert(entry)
        }

        dismiss()
    }
}

// Isolated structs so @Query changes don't re-render LogTimeSheet text fields.

private struct ProjectFilterPickerRow: View {
    @Query(sort: \Task.summary) private var allTasks: [Task]
    @Binding var selectedProject: Project?
    var isPresented: Binding<Bool>? = nil
    var autoFocus: Bool = false

    private var projectsWithTasks: [Project] {
        var seen = Set<UUID>()
        return allTasks
            .compactMap(\.project)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        FuzzyPickerField(
            allItems: projectsWithTasks,
            selectedItem: $selectedProject,
            label: { $0.name },
            chipColor: AppTheme.project,
            tapArea: true,
            emptyLabel: "Any project",
            isPresented: isPresented,
            autoFocus: autoFocus
        )
    }
}

private struct TaskPickerRow: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Task.summary) private var allTasks: [Task]
    @Binding var selectedTask: Task?
    var projectFilter: Project?
    var onChangeProject: () -> Void = {}
    var onClearProject: () -> Void = {}

    private var tasksForPicker: [Task] {
        guard let proj = projectFilter else { return allTasks }
        return allTasks.filter { $0.project?.id == proj.id }
    }

    private var tagFilters: [PickerFilter<Task>] {
        var seen = Set<String>()
        return tasksForPicker
            .flatMap(\.tags)
            .filter { seen.insert($0).inserted }
            .sorted()
            .map { tag in
                PickerFilter(id: "tag:\(tag)", label: "#\(tag)", chipColor: AppTheme.tag, group: "Tag") {
                    $0.tags.contains(tag)
                }
            }
    }

    // Rendered inside the popover above the Tag chips: shows the active project
    // as a chip (tap label → change, × → clear) or "Any project" when none set.
    private var projectLeadContent: AnyView {
        let proj = projectFilter
        let change = onChangeProject
        let clear = onClearProject
        return AnyView(
            HStack(alignment: .center, spacing: 0) {
                Text("Project")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 76, alignment: .trailing)
                    .padding(.trailing, 8)
                if let proj {
                    HStack(spacing: 3) {
                        Button { change() } label: {
                            Text(proj.name)
                                .font(AppTheme.interfaceFont(size: 10.5, weight: .regular))
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        Button { clear() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.leading, 7).padding(.trailing, 5).padding(.vertical, 3)
                    .background(AppTheme.chipBackground(AppTheme.project))
                    .foregroundStyle(AppTheme.project)
                    .overlay(Capsule().stroke(AppTheme.project.opacity(0.85), lineWidth: 1))
                    .clipShape(Capsule())
                } else {
                    Button { change() } label: {
                        Text("Any project")
                            .font(.callout)
                            .foregroundStyle(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        )
    }

    var body: some View {
        FuzzyPickerField(
            allItems: tasksForPicker,
            selectedItem: $selectedTask,
            label: { $0.summary },
            chipColor: AppTheme.accent,
            onCreateItem: { makeTask($0) },
            tapArea: true,
            emptyLabel: "None — tap to select task",
            filters: tagFilters.isEmpty ? nil : tagFilters,
            filterLeadContent: projectLeadContent
        )
    }

    // Create a new Task on the fly while selecting one to log time against (auto-selected).
    private func makeTask(_ summary: String) -> Task? {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let task = Task(summary: trimmed)
        modelContext.insert(task)
        return task
    }
}
