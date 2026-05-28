import SwiftUI
import SwiftData

struct TimesheetView: View {
    @Query(sort: \Task.completedAt, order: .reverse) private var allTasks: [Task]
    @Query(sort: \Project.name) private var projects: [Project]

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

    private var tasksInRange: [Task] {
        TimesheetComputation.tasksInRange(allTasks: allTasks, interval: rangeInterval)
    }

    private var totalHours: Double {
        TimesheetComputation.totalHours(tasks: tasksInRange)
    }

    private func hours(for project: Project) -> Double {
        TimesheetComputation.hours(for: project, tasks: tasksInRange)
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
                    Text("\(String(format: "%.1f", totalHours / 7.6)) d  ·  \(tasksInRange.count) tasks")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var projectBreakdown: some View {
        GroupBox("By Project") {
            let used = projects.filter { hours(for: $0) > 0 }
            if used.isEmpty {
                Text("No completed tasks with duration in this range.")
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
