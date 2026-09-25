import SwiftUI
import SwiftData

// A project's standing tasks: perpetual, stateless work that never completes — "keep the inbox at
// zero", "review the literature". They accumulate time but have no status cycle, never rank in
// urgency, never reach the planning board, and are created already-reviewed so they can't hold up a
// curation gate.
//
// Shared by ProjectDetailView and CurationView so both show the same section.
struct StandingTasksSection: View {
    let project: Project

    @Environment(\.modelContext) private var modelContext
    @Environment(WorkspaceModel.self) private var workspace
    @Query(sort: \Task.createdAt) private var allTasks: [Task]
    @Query(sort: \Person.name) private var allPeople: [Person]

    @State private var newSummary = ""
    @State private var loggingTask: Task?
    @FocusState private var addFocused: Bool

    private var standing: [Task] {
        allTasks.filter { $0.isStanding && $0.project?.id == project.id }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        DaySectionHeader(title: "Standing (\(standing.count))")
        VStack(alignment: .leading, spacing: 4) {
            if standing.isEmpty {
                Text("No standing tasks — ongoing work that never completes but accumulates time.")
                    .font(AppTheme.bodyFont(size: 11))
                    .foregroundStyle(AppTheme.mutedText)
            }
            ForEach(standing) { task in
                StandingTaskRow(task: task, onLogTime: { loggingTask = task })
            }
            addField
        }
        .padding(.horizontal)
        .sheet(item: $loggingTask) { t in
            LogTimeSheet(presetTask: t, presetDate: Date())
        }
    }

    private var addField: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle").font(.caption).foregroundStyle(AppTheme.mutedText)
            TextField("Add a standing task…", text: $newSummary)
                .textFieldStyle(.roundedBorder)
                .focused($addFocused)
                .onSubmit(add)
            if !newSummary.trimmingCharacters(in: .whitespaces).isEmpty {
                Button("Add", action: add).font(AppTheme.bodyFont(size: 12))
            }
        }
        .padding(.top, 2)
    }

    private func add() {
        let trimmed = newSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let task = Task(summary: trimmed)
        modelContext.insert(task)
        task.project = project
        task.assignee = AppSettingsStore.myPersonID.flatMap { id in allPeople.first { $0.id == id } }
        // makeStanding() also clears the triage flag and any horizon, so it can never block a curation
        // gate or show up on the planning board.
        task.makeStanding()
        newSummary = ""
        addFocused = true
    }
}

// One standing task: no status control (it has no status cycle), just its logged total and a way to
// add more time.
struct StandingTaskRow: View {
    @Bindable var task: Task
    var onLogTime: () -> Void

    @Environment(WorkspaceModel.self) private var workspace

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "infinity")
                .font(.caption)
                .foregroundStyle(AppTheme.duration)
                .help("Standing task — perpetual, no status")
            Text(task.summary)
                .font(AppTheme.bodyFont(size: 13))
                .foregroundStyle(AppTheme.text)
                .lineLimit(1)
            Spacer(minLength: 0)
            if task.loggedHoursNormalized > 0 {
                Chip(label: TimeFormat.hours(task.loggedHoursNormalized), color: AppTheme.duration)
            }
            Button(action: onLogTime) {
                Image(systemName: "clock.badge.plus").font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.duration)
            .help("Log time")
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { workspace.focusOrOpen(.task(task.persistentModelID)) }
        .padding(.vertical, 2)
    }
}
