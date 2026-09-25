import SwiftUI
import SwiftData

// The diary's standing-task strip: a fixed row pinned under the task panel for logging time against
// perpetual work that never appears in the action buckets (see DayTaskBuckets, which excludes it).
//
// Time books to the shown diary day's current time — or the real weekend time when parked on the green
// Monday, so weekend work lands in Friday's overtime, exactly like the panel's quick-add.
struct StandingTaskStrip: View {
    let date: Date

    @Environment(\.modelContext) private var modelContext
    @Environment(WorkspaceModel.self) private var workspace
    @Query(sort: \Task.createdAt) private var allTasks: [Task]
    @Query(sort: \Person.name) private var allPeople: [Person]

    @State private var isExpanded = true

    private var me: Person? {
        AppSettingsStore.myPersonID.flatMap { id in allPeople.first { $0.id == id } }
    }

    /// Mine when "Me" is configured, else all — matching how DayTaskPanel scopes itself.
    private var standing: [Task] {
        allTasks.filter { task in
            guard task.isStanding else { return false }
            guard let me else { return true }
            return task.assignee?.id == me.id
        }
        .sorted { $0.summary.localizedCaseInsensitiveCompare($1.summary) == .orderedAscending }
    }

    /// Hours logged against a standing task on the shown day, so the strip shows today's effort.
    private func hoursToday(_ task: Task) -> Double {
        let window = WeekendPolicy.workRange(for: date)
        return task.timeEntries.filter { window.contains($0.date) }
            .reduce(0) { $0 + $1.duration.hoursNormalized }
    }

    var body: some View {
        if !standing.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Divider()
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9)).foregroundStyle(AppTheme.mutedText)
                        Image(systemName: "infinity").font(.caption).foregroundStyle(AppTheme.duration)
                        Text("Standing").font(AppTheme.bodyFont(size: 12).weight(.semibold))
                            .foregroundStyle(AppTheme.text)
                        Text("\(standing.count)").font(AppTheme.bodyFont(size: 11))
                            .foregroundStyle(AppTheme.mutedText).monospacedDigit()
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 6)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(standing) { task in row(task) }
                    }
                    .padding(.horizontal, 10).padding(.bottom, 8)
                }
            }
            .background(AppTheme.cardRaised.opacity(0.25))
        }
    }

    private func row(_ task: Task) -> some View {
        HStack(spacing: 6) {
            Text(task.summary)
                .font(AppTheme.bodyFont(size: 12))
                .foregroundStyle(AppTheme.text)
                .lineLimit(1)
            if let project = task.project {
                Chip(label: project.name, color: AppTheme.project)
            }
            Spacer(minLength: 4)
            let today = hoursToday(task)
            if today > 0 {
                Chip(label: TimeFormat.short(hours: today), color: AppTheme.duration)
            }
            ForEach([15, 30, 60], id: \.self) { minutes in
                Button(minutes == 60 ? "1h" : "\(minutes)m") { logTime(minutes, on: task) }
                    .buttonStyle(.plain)
                    .font(AppTheme.bodyFont(size: 10))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(AppTheme.chipBackground(AppTheme.duration), in: Capsule())
                    .foregroundStyle(AppTheme.duration)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { workspace.focusOrOpen(.task(task.persistentModelID)) }
    }

    private func logTime(_ minutes: Int, on task: Task) {
        let nextOrder = (task.timeEntries.map(\.sortOrder).max() ?? -1) + 1
        let entry = TaskTimeEntry(date: WeekendPolicy.logNowDate(viewedDate: date),
                                  duration: Duration(value: Double(minutes) / 60.0, unit: .h),
                                  comment: nil, sortOrder: nextOrder)
        entry.task = task
        modelContext.insert(entry)
        // No status change: a standing task has no status cycle to advance.
    }
}
