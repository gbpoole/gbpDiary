import Foundation

// Chat is the one place that must fold weekends like the rest of the diary (Mon–Fri): the model narrates
// whatever date it is handed, so a raw Saturday date leaks "Saturday work". This picks the fold direction
// by source kind — work/activity (meetings, logged time) books BACK to the preceding Friday; inbound
// (received email, task due/scheduled) folds FORWARD to the next Monday; day/note records are already
// weekday-anchored. Applied to every date that enters the Chat corpus text, its sort date, and the time
// records — so the model never sees a weekend and interval/week bucketing stays weekend-correct.
nonisolated enum ChatWeekendFold {
    static func fold(_ date: Date, kind: ChatSourceKind, calendar: Calendar = .current) -> Date {
        switch kind {
        case .meeting:
            // Work happened on a weekend → overtime on the preceding Friday.
            return WeekendPolicy.workWeekday(for: date, calendar: calendar)
        case .email, .task:
            // Inbound (received / scheduled / due) → the next working Monday.
            return WeekendPolicy.weekday(for: date, calendar: calendar)
        case .day, .note, .project, .person, .institution, .document, .attachment:
            // Already weekday-anchored (or dateless) — leave the day, just normalise weekends forward.
            return WeekendPolicy.weekday(for: date, calendar: calendar)
        }
    }

    /// Logged time is always work → the preceding Friday when it lands on a weekend.
    static func foldWork(_ date: Date, calendar: Calendar = .current) -> Date {
        WeekendPolicy.workWeekday(for: date, calendar: calendar)
    }
}
