import SwiftUI
import SwiftData

struct WeekView: View {
    let weekOf: Date

    @Query(sort: \Task.createdAt) private var allTasks: [Task]
    @Query private var allDayRecords: [DayRecord]
    @State private var banner: BannerMessage? = nil

    private var weekDays: [Date] {
        let cal = Calendar.current
        guard let weekStart = cal.dateInterval(of: .weekOfYear, for: weekOf)?.start else {
            return []
        }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }

    var body: some View {
        ScrollView {
            // VStack not LazyVStack: each day section contains DayPageContent which has a nested
            // ScrollView. LazyVStack's lazy measurement oscillates with nested ScrollViews,
            // causing an infinite layout loop (ever-growing memory, high CPU on scroll).
            VStack(alignment: .leading, spacing: 0) {
                ForEach(weekDays, id: \.self) { day in
                    weekDaySection(for: day)
                }
            }
            .padding(.bottom, 20)
        }
        .overlay(alignment: .bottom) {
            if let msg = banner { bannerView(msg) }
        }
        .animation(.easeInOut(duration: 0.25), value: banner)
    }

    private func showBanner(_ msg: BannerMessage) {
        banner = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { banner = nil }
    }

    private func bannerView(_ msg: BannerMessage) -> some View {
        HStack(spacing: 8) {
            Image(systemName: msg.systemImage).foregroundStyle(msg.tint)
            Text(msg.text).font(.callout)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 4)
        .padding(.bottom, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
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

            DayPageContent(date: day, dayRecord: record, allTasks: allTasks, showTaskSections: false,
                           showActionBar: false, onShowBanner: showBanner)
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
