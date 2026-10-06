import Foundation

// The follow-up history rules, kept pure so the follow-up modal, the task page's editable list and the
// one-time launch migration cannot disagree.
//
// **A follow-up is a DAY, never a time.** "Follow up today" means today, so every stored date is
// normalised to the start of its day. That makes the parked/due split fall straight out of the clock with
// no extra rule: today's follow-up is already due (`now >= followUpAt`), any later day is parked.
//
// **The pending entry is the LAST one in append order** (and only while a follow-up is actually live);
// `Task.followUpAt` mirrors its date. *Display* order is a separate concern — date-descending — so the
// list still reads as a timeline after an entry has been corrected to an earlier date.
enum FollowUpHistory {

    /// Day granularity: strip the time of day.
    static func day(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    /// A follow-up can be set for today or any later day, never the past.
    static func isDateAllowed(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        day(date, calendar: calendar) >= day(now, calendar: calendar)
    }

    /// Both verbs — Add another follow-up and Correct last entry — share one save gate: a real reason,
    /// and a date that isn't in the past.
    static func canSave(note: String, date: Date,
                        now: Date = Date(), calendar: Calendar = .current) -> Bool {
        !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && isDateAllowed(date, now: now, calendar: calendar)
    }

    /// Newest-dated first. Ties keep the later-*added* entry first, so the order is total and stable.
    static func displayOrder(_ entries: [FollowUpEntry]) -> [FollowUpEntry] {
        entries.enumerated()
            .sorted { l, r in
                l.element.date == r.element.date ? l.offset > r.offset : l.element.date > r.element.date
            }
            .map(\.element)
    }

    /// Append a follow-up; the new entry becomes the pending one.
    static func adding(date: Date, note: String, to entries: [FollowUpEntry],
                       calendar: Calendar = .current) -> [FollowUpEntry] {
        entries + [FollowUpEntry(date: day(date, calendar: calendar), note: note)]
    }

    /// Edit one entry in place, keeping its id and its position in append order (so which entry is
    /// pending never changes as a side effect of a correction).
    static func updating(entryID: UUID, date: Date, note: String, in entries: [FollowUpEntry],
                         calendar: Calendar = .current) -> [FollowUpEntry] {
        entries.map { entry in
            guard entry.id == entryID else { return entry }
            return FollowUpEntry(id: entry.id, date: day(date, calendar: calendar), note: note)
        }
    }

    static func removing(entryID: UUID, from entries: [FollowUpEntry]) -> [FollowUpEntry] {
        entries.filter { $0.id != entryID }
    }

    /// One-time normalisation for rows written before follow-ups were day-granular: strip the time of day
    /// from the task's own date and from every entry. Writing the history back also *persists* the ids
    /// that decoding synthesises for legacy, id-less entries.
    static func normalized(followUpAt: Date?, entries: [FollowUpEntry],
                           calendar: Calendar = .current)
    -> (followUpAt: Date?, entries: [FollowUpEntry]) {
        (followUpAt.map { day($0, calendar: calendar) },
         entries.map { FollowUpEntry(id: $0.id, date: day($0.date, calendar: calendar), note: $0.note) })
    }

    /// Whether any of this task's follow-up dates still carries a time of day.
    static func needsNormalizing(followUpAt: Date?, entries: [FollowUpEntry],
                                 calendar: Calendar = .current) -> Bool {
        let fixed = normalized(followUpAt: followUpAt, entries: entries, calendar: calendar)
        return fixed.followUpAt != followUpAt || fixed.entries.map(\.date) != entries.map(\.date)
    }
}
