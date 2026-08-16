import Foundation

// The diary is a Mon–Fri surface: weekends aren't their own days. This is the single source of truth for
// how Saturday/Sunday fold into weekdays:
//   • inbound/forward content (received emails, scheduled/due tasks) folds FORWARD into the next Monday;
//   • work done on the weekend (time entries, sent emails, completed-task activity) folds BACK into the
//     preceding Friday as overtime.
// Pure/testable; uses `Calendar.isDateInWeekend` so it honours the locale's weekend definition.
enum WeekendPolicy {
    static func isWeekend(_ date: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDateInWeekend(date)
    }

    /// The diary weekday a date belongs to: a weekend date resolves FORWARD to the next weekday (Monday);
    /// a weekday is itself. Result is start-of-day.
    static func weekday(for date: Date, calendar: Calendar = .current) -> Date {
        var day = calendar.startOfDay(for: date)
        while isWeekend(day, calendar: calendar) {
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        }
        return day
    }

    /// The diary weekday **work** belongs to: a weekend date resolves BACK to the preceding weekday
    /// (Friday) as overtime; a weekday is itself. Result is start-of-day. Mirror of `weekday(for:)`.
    static func workWeekday(for date: Date, calendar: Calendar = .current) -> Date {
        var day = calendar.startOfDay(for: date)
        while isWeekend(day, calendar: calendar) {
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return day
    }

    /// Step whole weekdays, skipping Sat/Sun (Fri +1 → Mon; Mon −1 → Fri). Start-of-day result.
    static func steppedWeekday(from date: Date, delta: Int, calendar: Calendar = .current) -> Date {
        var day = calendar.startOfDay(for: date)
        guard delta != 0 else { return day }
        let step = delta > 0 ? 1 : -1
        for _ in 0..<abs(delta) {
            repeat {
                day = calendar.date(byAdding: .day, value: step, to: day) ?? day
            } while isWeekend(day, calendar: calendar)
        }
        return day
    }

    /// The weekdays (Mon–Fri) of the week containing `date`, in order.
    static func weekdays(ofWeekContaining date: Date, calendar: Calendar = .current) -> [Date] {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { return [] }
        return (0..<7)
            .compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
            .filter { !isWeekend($0, calendar: calendar) }
    }

    /// Calendar days folded into a weekday for **inbound/forward** content: a Monday extends back over the
    /// two preceding weekend days (Sat..<Tue); any other weekday is just that day. Half-open.
    static func forwardRange(for weekday: Date, calendar: Calendar = .current) -> Range<Date> {
        let dayStart = calendar.startOfDay(for: weekday)
        let end = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        var start = dayStart
        var probe = calendar.date(byAdding: .day, value: -1, to: start) ?? start
        while isWeekend(probe, calendar: calendar) {
            start = probe
            probe = calendar.date(byAdding: .day, value: -1, to: probe) ?? probe
        }
        return start..<end
    }

    /// Calendar days folded into a weekday for **work** content: a Friday extends forward over the
    /// following weekend (Fri..<Mon); any other weekday is just that day. Half-open.
    static func workRange(for weekday: Date, calendar: Calendar = .current) -> Range<Date> {
        let start = calendar.startOfDay(for: weekday)
        var end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        while isWeekend(end, calendar: calendar) {
            end = calendar.date(byAdding: .day, value: 1, to: end) ?? end
        }
        return start..<end
    }

    /// The timestamp a "log time now" action should stamp for the viewed diary day (rounded to the
    /// nearest quarter-hour). Normally it's the current time-of-day on the viewed day; but when it is
    /// actually the **weekend** and the diary is parked on the weekday that weekend folds into (the green
    /// Monday), it returns the real weekend `now` — so the logged work books to Friday's overtime rather
    /// than to Monday.
    static func logNowDate(viewedDate: Date, now: Date = Date(), calendar: Calendar = .current) -> Date {
        let stamp = roundedToQuarterHour(now)
        if isWeekend(now, calendar: calendar),
           calendar.startOfDay(for: viewedDate) == weekday(for: now, calendar: calendar) {
            return stamp
        }
        let h = calendar.component(.hour, from: stamp)
        let m = calendar.component(.minute, from: stamp)
        return calendar.date(bySettingHour: h, minute: m, second: 0,
                             of: calendar.startOfDay(for: viewedDate)) ?? viewedDate
    }

    private static func roundedToQuarterHour(_ date: Date) -> Date {
        let quarter = 15.0 * 60.0
        let t = (date.timeIntervalSinceReferenceDate / quarter).rounded() * quarter
        return Date(timeIntervalSinceReferenceDate: t)
    }
}
