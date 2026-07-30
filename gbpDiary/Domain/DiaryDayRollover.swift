import Foundation

// Decides whether the diary should roll its shown day forward to the real "today" when the app
// reactivates. Pure and testable: the diary only follows the clock when it is *tracking today*
// (i.e. the user is parked on what was today, not a day they deliberately navigated to) and the
// shown day has since fallen into the past.
enum DiaryDayRollover {
    /// The start-of-day the diary should advance to, or nil to stay on the current day.
    static func rolledForwardDate(currentDate: Date, tracksToday: Bool, now: Date,
                                  calendar: Calendar = .current) -> Date? {
        guard tracksToday else { return nil }
        let today = calendar.startOfDay(for: now)
        return calendar.startOfDay(for: currentDate) < today ? today : nil
    }
}
