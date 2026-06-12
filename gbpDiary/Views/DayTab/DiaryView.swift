import SwiftUI
import SwiftData

enum DiaryMode: String, CaseIterable {
    case day = "Day"
    case week = "Week"
}

struct DiaryView: View {
    @State private var mode: DiaryMode = .day
    @State private var currentDate: Date = Calendar.current.startOfDay(for: Date())

    @Query(sort: \Task.createdAt) private var allTasks: [Task]
    @Query private var allDayRecords: [DayRecord]

    private var dayRecord: DayRecord? {
        allDayRecords.first { Calendar.current.isDate($0.date, inSameDayAs: currentDate) }
    }

    var body: some View {
        if mode == .day {
            NavigationSplitView {
                DayTaskSidebar(date: currentDate, dayRecord: dayRecord, allTasks: allTasks)
                    .background(AppTheme.sidebarBackground)
            } detail: {
                VStack(spacing: 0) {
                    diaryBar
                    Divider()
                    DayView(date: currentDate, dayRecord: dayRecord, allTasks: allTasks)
                }
                .background(AppTheme.background)
            }
        } else {
            VStack(spacing: 0) {
                diaryBar
                Divider()
                WeekView(weekOf: currentDate)
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
            Button("Today") { currentDate = Calendar.current.startOfDay(for: Date()) }
                .disabled(isCurrentPeriod)

            Text(dateLabel)
                .font(AppTheme.interfaceFont(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)

            Picker("", selection: $mode) {
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
        switch mode {
        case .day:
            return Calendar.current.isDateInToday(currentDate)
        case .week:
            return Calendar.current.isDate(currentDate, equalTo: Date(), toGranularity: .weekOfYear)
        }
    }

    private var dateLabel: String {
        switch mode {
        case .day:
            return currentDate.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
        case .week:
            let cal = Calendar.current
            guard let start = cal.dateInterval(of: .weekOfYear, for: currentDate)?.start,
                  let end = cal.date(byAdding: .day, value: 6, to: start) else { return "" }
            return "\(start.formatted(.dateTime.day().month())) – \(end.formatted(.dateTime.day().month().year()))"
        }
    }

    private func stepDate(_ delta: Int) {
        let unit: Calendar.Component = mode == .day ? .day : .weekOfYear
        currentDate = Calendar.current.date(byAdding: unit, value: delta, to: currentDate) ?? currentDate
    }
}
