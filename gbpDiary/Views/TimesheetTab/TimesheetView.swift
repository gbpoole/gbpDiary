import SwiftUI
import SwiftData

struct TimesheetView: View {
    @Query(sort: \Task.completedAt, order: .reverse) private var allTasks: [Task]
    @Query(sort: \Project.name) private var projects: [Project]
    @Query(sort: \TaskTimeEntry.date, order: .reverse) private var allEntries: [TaskTimeEntry]

    @State private var selectedRange: TimesheetRange = .pastWeek
    @State private var customStart: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    @State private var customEnd: Date = Date()

    private var rangeInterval: DateInterval {
        TimesheetComputation.rangeInterval(
            selectedRange: selectedRange,
            customStart: customStart,
            customEnd: customEnd
        )
    }

    private var entriesInRange: [TaskTimeEntry] {
        TimesheetComputation.entriesInRange(allEntries: allEntries, interval: rangeInterval)
    }

    // Legacy: tasks with no time entries that have a duration field set.
    private var legacyTasksInRange: [Task] {
        TimesheetComputation.tasksInRange(allTasks: allTasks, interval: rangeInterval)
            .filter { $0.timeEntries.isEmpty }
    }

    private var entryHours: Double {
        TimesheetComputation.totalHours(entries: entriesInRange)
    }

    private var legacyHours: Double {
        TimesheetComputation.totalHours(tasks: legacyTasksInRange)
    }

    private var totalHours: Double { entryHours + legacyHours }

    private var totalTaskCount: Int { Set(entriesInRange.compactMap(\.task?.id)).union(Set(legacyTasksInRange.map(\.id))).count }

    private func hours(for project: Project) -> Double {
        TimesheetComputation.hours(for: project, entries: entriesInRange)
        + TimesheetComputation.hours(for: project, tasks: legacyTasksInRange)
    }

    var body: some View {
        VStack(spacing: 0) {
            rangeBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    totalCard
                    projectBreakdown
                }
                .padding()
            }
        }
    }

    private var rangeBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Range", selection: $selectedRange) {
                ForEach(TimesheetRange.allCases, id: \.self) { r in
                    Text(r.rawValue).tag(r)
                }
            }
            .pickerStyle(.segmented)
            if selectedRange == .custom {
                HStack {
                    DatePicker("From", selection: $customStart, displayedComponents: .date)
                    DatePicker("To", selection: $customEnd, displayedComponents: .date)
                }
                .labelsHidden()
            }
        }
        .padding()
    }

    private var totalCard: some View {
        GroupBox("Total") {
            HStack {
                VStack(alignment: .leading) {
                    Text("\(String(format: "%.1f", totalHours)) h")
                        .font(.largeTitle.bold())
                    Text("\(String(format: "%.1f", totalHours / 7.6)) d  ·  \(totalTaskCount) tasks")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if legacyHours > 0 {
                        Text("Includes \(String(format: "%.1f", legacyHours)) h from tasks without time entries")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
    }

    private var projectBreakdown: some View {
        GroupBox("By Project") {
            let used = projects.filter { hours(for: $0) > 0 }
            if used.isEmpty {
                Text("No logged time in this range.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(used) { project in
                        let h = hours(for: project)
                        HStack {
                            Text(project.name)
                            Spacer()
                            Text("\(String(format: "%.1f", h)) h")
                                .monospacedDigit()
                            Text("(\(Int(h / totalHours * 100))%)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }
}
