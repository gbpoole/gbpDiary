import SwiftUI
import SwiftData

struct WeekView: View {
    let weekOf: Date

    @Query(sort: \Task.createdAt) private var allTasks: [Task]
    @Query private var allDayRecords: [DayRecord]

    private var weekDays: [Date] {
        let cal = Calendar.current
        guard let weekStart = cal.dateInterval(of: .weekOfYear, for: weekOf)?.start else {
            return []
        }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(weekDays, id: \.self) { day in
                    weekDaySection(for: day)
                }
            }
            .padding(.bottom, 20)
        }
    }

    @ViewBuilder
    private func weekDaySection(for day: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(day)
        let record = allDayRecords.first { Calendar.current.isDate($0.date, inSameDayAs: day) }

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text(day, format: .dateTime.weekday(.wide))
                    .font(.title2.bold())
                    .foregroundStyle(isToday ? Color.accentColor : .primary)
                Text(day, format: .dateTime.day().month(.wide).year())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 28)
            .padding(.bottom, 6)

            Divider()
                .padding(.horizontal)

            DayPageContent(date: day, dayRecord: record, allTasks: allTasks, showBacklog: false)
                .padding(.bottom, 8)
        }
        .background(isToday ? Color.accentColor.opacity(0.04) : Color.clear)
    }
}

#Preview {
    WeekView(weekOf: Date())
        .modelContainer(for: [Task.self, DayRecord.self, DayEntry.self, Project.self,
                               Person.self, Institution.self, Minutes.self],
                        inMemory: true)
        .frame(width: 680, height: 800)
}
