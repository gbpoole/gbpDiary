import Foundation

// Persistent state for the Diary browsing surface. Held at the workspace level so the selected
// date and Day/Week mode survive switching to another tab (e.g. an open meeting) and back —
// DiaryView itself is recreated on tab switch and must not own this in transient @State.
@Observable final class DiaryState {
    // The diary is Mon–Fri: a weekend "today" resolves forward to the upcoming Monday.
    var currentDate: Date = WeekendPolicy.weekday(for: Date())
    var mode: DiaryMode = .day
    // Set to request the day view scroll to a specific note; cleared once consumed.
    var scrollTargetNoteId: UUID? = nil
    // Set to request the day view scroll to a specific logged time entry (Activity section); cleared once
    // consumed. Used when jumping from a task's time-entry list to the diary.
    var scrollTargetEntryId: UUID? = nil
    // Set to request the day view scroll to a specific focus block (Activity section); cleared once consumed.
    // Used when jumping from a task's focus-block time-log row to the diary.
    var scrollTargetBlockId: UUID? = nil
    // True while the diary is parked on "today" (initial state, the Today button, or navigating to
    // today), so it can roll forward when the wall-clock day changes. Deliberate navigation to any
    // other day clears it. See DiaryDayRollover.
    var tracksToday: Bool = true

    /// Move to `date` — snapping a weekend to its Monday — and update `tracksToday` from whether the
    /// destination is the weekday "today" belongs to.
    func goTo(_ date: Date, calendar: Calendar = .current) {
        currentDate = WeekendPolicy.weekday(for: date, calendar: calendar)
        tracksToday = currentDate == WeekendPolicy.weekday(for: Date(), calendar: calendar)
    }

    /// On reactivation/appear, advance to today if we were tracking it and it is now in the past.
    func advanceIfTrackingToday(now: Date = Date(), calendar: Calendar = .current) {
        if let forward = DiaryDayRollover.rolledForwardDate(currentDate: currentDate,
                                                            tracksToday: tracksToday, now: now,
                                                            calendar: calendar) {
            currentDate = forward
        }
    }
}
