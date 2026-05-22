import SwiftUI
import SwiftData

enum TimesheetRange: String, CaseIterable {
    case today = "Today"
    case yesterday = "Yesterday"
    case pastWeek = "Past Week"
    case currentMonth = "This Month"
    case currentYear = "This Year"
    case custom = "Custom"
}

struct TimesheetView: View {
    @Query(sort: \Task.completedAt, order: .reverse) private var allTasks: [Task]
    @Query(sort: \Project.name) private var projects: [Project]

    @State private var selectedRange: TimesheetRange = .pastWeek
    @State private var customStart: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    @State private var customEnd: Date = Date()

    private var rangeInterval: DateInterval {
        let cal = Calendar.current
        let now = Date()
        switch selectedRange {
        case .today:
            let start = cal.startOfDay(for: now)
            return DateInterval(start: start, end: cal.date(byAdding: .day, value: 1, to: start)!)
        case .yesterday:
            let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
            let start = cal.startOfDay(for: yesterday)
            return DateInterval(start: start, end: cal.date(byAdding: .day, value: 1, to: start)!)
        case .pastWeek:
            return DateInterval(start: cal.date(byAdding: .day, value: -7, to: now)!, end: now)
        case .currentMonth:
            let comps = cal.dateComponents([.year, .month], from: now)
            let start = cal.date(from: comps)!
            return DateInterval(start: start, end: now)
        case .currentYear:
            let comps = cal.dateComponents([.year], from: now)
            let start = cal.date(from: comps)!
            return DateInterval(start: start, end: now)
        case .custom:
            return DateInterval(start: customStart, end: customEnd)
        }
    }

    private var tasksInRange: [Task] {
        allTasks.filter {
            guard let c = $0.completedAt, let _ = $0.duration else { return false }
            return rangeInterval.contains(c)
        }
    }

    private var totalHours: Double {
        tasksInRange.compactMap { $0.duration?.hoursNormalized }.reduce(0, +)
    }

    private func hours(for project: Project) -> Double {
        tasksInRange
            .filter { $0.project?.id == project.id }
            .compactMap { $0.duration?.hoursNormalized }
            .reduce(0, +)
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
