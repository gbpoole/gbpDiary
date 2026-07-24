import SwiftUI
import SwiftData

enum DiaryMode: String, CaseIterable {
    case day = "Day"
    case week = "Week"
}

struct DiaryView: View {
    @Environment(DiaryState.self) private var diary

    @Query(sort: \Task.createdAt) private var allTasks: [Task]
    @Query private var allDayRecords: [DayRecord]

    private var dayRecord: DayRecord? {
        allDayRecords.first { Calendar.current.isDate($0.date, inSameDayAs: diary.currentDate) }
    }

    var body: some View {
        if diary.mode == .day {
            // Plain HStack (not a nested NavigationSplitView) since the Diary is hosted inside the
            // workspace's NavigationSplitView; nesting split views misbehaves on macOS.
            HStack(spacing: 0) {
                DayTaskSidebar(date: diary.currentDate, dayRecord: dayRecord, allTasks: allTasks)
                    .frame(width: 260)
                    .background(AppTheme.sidebarBackground)
                Divider()
                VStack(spacing: 0) {
                    diaryBar
                    Divider()
                    DayView(date: diary.currentDate, dayRecord: dayRecord, allTasks: allTasks)
                }
                .frame(maxWidth: .infinity)
                .background(AppTheme.background)
            }
        } else {
            VStack(spacing: 0) {
                diaryBar
                Divider()
                WeekView(weekOf: diary.currentDate)
            }
            .background(AppTheme.background)
        }
    }

    private var diaryBar: some View {
        HStack(spacing: 6) {
            Button { stepDate(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
            Button { stepDate(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
            Button("Today") { diary.currentDate = Calendar.current.startOfDay(for: Date()) }
                .disabled(isCurrentPeriod)

            Text(dateLabel)
                .font(AppTheme.interfaceFont(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)

            Picker("", selection: Binding(get: { diary.mode }, set: { diary.mode = $0 })) {
                ForEach(DiaryMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(AppTheme.sidebarBackground)
    }

    private var isCurrentPeriod: Bool {
        switch diary.mode {
        case .day:
            return Calendar.current.isDateInToday(diary.currentDate)
        case .week:
            return Calendar.current.isDate(diary.currentDate, equalTo: Date(), toGranularity: .weekOfYear)
        }
    }

    private var dateLabel: String {
        switch diary.mode {
        case .day:
            return diary.currentDate.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
        case .week:
            let cal = Calendar.current
            guard let start = cal.dateInterval(of: .weekOfYear, for: diary.currentDate)?.start,
                  let end = cal.date(byAdding: .day, value: 6, to: start) else { return "" }
            return "\(start.formatted(.dateTime.day().month())) – \(end.formatted(.dateTime.day().month().year()))"
        }
    }

    private func stepDate(_ delta: Int) {
        let unit: Calendar.Component = diary.mode == .day ? .day : .weekOfYear
        diary.currentDate = Calendar.current.date(byAdding: unit, value: delta, to: diary.currentDate) ?? diary.currentDate
    }
}
