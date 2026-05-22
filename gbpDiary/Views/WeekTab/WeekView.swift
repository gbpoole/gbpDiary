import SwiftUI
import SwiftData

struct WeekView: View {
    let weekOf: Date

    @Query(sort: \Task.createdAt) private var allTasks: [Task]

    private var weekDays: [Date] {
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: weekOf)?.start ?? weekOf
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 1) {
                ForEach(weekDays, id: \.self) { day in
                    WeekDayColumn(day: day, tasks: tasks(for: day))
                }
            }
        }
    }

    private func tasks(for day: Date) -> [Task] {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return allTasks.filter {
            let scheduled = $0.scheduledAt.map { $0 >= start && $0 < end } ?? false
            let completed = $0.completedAt.map { $0 >= start && $0 < end } ?? false
            return scheduled || completed
        }
    }
}

private struct WeekDayColumn: View {
    let day: Date
    let tasks: [Task]

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 2) {
                Text(day, format: .dateTime.weekday(.short))
                    .font(.caption.bold())
                Text(day, format: .dateTime.day())
                    .font(.title3.bold())
                    .foregroundStyle(isToday ? Color.accentColor : Color.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isToday ? Color.accentColor.opacity(0.08) : Color.clear)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(tasks) { task in
                        WeekTaskChip(task: task)
                    }
                    if tasks.isEmpty {
                        Color.clear.frame(height: 40)
                    }
                }
                .padding(6)
            }
        }
        .frame(minWidth: 140, maxWidth: 180)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3), lineWidth: 0.5))
    }
}

private struct WeekTaskChip: View {
    let task: Task

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                .font(.caption2)
                .foregroundStyle(task.status == .completed ? .green : .secondary)
            Text(task.title)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(task.status == .cancelled ? .secondary : .primary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
