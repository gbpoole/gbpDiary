import Foundation

// Which meetings belong to a diary day. A meeting's day is derived from its OWN `meetingAt` and nothing
// else, so it appears where it says it does and re-dating it MOVES it.
//
// It used to be anchored by a stored `DayEntry` on a `DayRecord`. That was a second source of truth, and
// the two disagreed from the moment of creation: adding a meeting while viewing Tuesday stamped `meetingAt`
// with `now` (Thursday) but filed the entry under Tuesday — and because membership was the stored entry,
// correcting the date afterwards could never move it.
//
// `WeekendPolicy.workRange` is used (not a bare calendar day) so a weekend meeting folds back into Friday
// like every other kind of logged work, keeping the diary and the time ledger in agreement.
nonisolated enum DayMeetingFiltering {
    /// The meetings belonging to `date`'s diary day, earliest first.
    static func meetings<M>(on date: Date, from all: [M], meetingAt: (M) -> Date,
                            calendar: Calendar = .current) -> [M] {
        let window = WeekendPolicy.workRange(for: date, calendar: calendar)
        return all.filter { window.contains(meetingAt($0)) }
            .sorted { meetingAt($0) < meetingAt($1) }
    }
}
