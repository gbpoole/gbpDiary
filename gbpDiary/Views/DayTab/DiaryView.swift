import SwiftUI
import SwiftData

enum DiaryMode: String, CaseIterable {
    case day = "Day"
    case week = "Week"
}

struct DiaryView: View {
    @Environment(DiaryState.self) private var diary
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \Task.createdAt) private var allTasks: [Task]
    @Query private var allDayRecords: [DayRecord]

    private var dayRecord: DayRecord? {
        allDayRecords.first { Calendar.current.isDate($0.date, inSameDayAs: diary.currentDate) }
    }

    var body: some View {
        content
            // Roll a stale "today" forward when the diary re-appears or the app reactivates, so a
            // meeting/task added after midnight files on the real today (not the day left on screen).
            .onAppear { diary.advanceIfTrackingToday() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { diary.advanceIfTrackingToday() }
            }
    }

    @ViewBuilder private var content: some View {
        if diary.mode == .day {
            VStack(spacing: 0) {
                diaryBar
                Divider()
                DayView(date: diary.currentDate, dayRecord: dayRecord, allTasks: allTasks)
            }
            .frame(maxWidth: .infinity)
            .background(AppTheme.background)
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
        // Green when viewing today/this week; accent otherwise, so "today" is instantly recognisable.
        let dateColor = isCurrentPeriod ? AppTheme.today : AppTheme.accent
        return HStack(spacing: 12) {
            // Date stepper — a single, colour-tinted control (calendar icon + prominent date) so
            // it reads clearly as day/week navigation, distinct from the tab back/forward above.
            HStack(spacing: 10) {
                Button { stepDate(-1) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(.plain)
                // Tapping the date jumps to today. Icon fills in on the current period; colour
                // (green today / accent otherwise) keeps "today" instantly recognisable.
                Button { diary.goTo(Date()) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: isCurrentPeriod ? "calendar.circle.fill" : "calendar")
                            .font(.system(size: 13))
                        Text(dateLabel)
                            .font(AppTheme.interfaceFont(size: 15, weight: .semibold))
                            .tracking(0.2)
                            .lineLimit(1)
                            .frame(width: 232, alignment: .center)   // fixed so the control doesn't jump
                    }
                    .foregroundStyle(dateColor)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isCurrentPeriod ? "Viewing today" : "Go to today")
                Button { stepDate(1) } label: {
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(dateColor.opacity(0.10), in: Capsule())
            .overlay(Capsule().strokeBorder(dateColor.opacity(0.28), lineWidth: 1))

            Spacer()

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
        let stepped = Calendar.current.date(byAdding: unit, value: delta, to: diary.currentDate) ?? diary.currentDate
        diary.goTo(stepped)
    }
}
