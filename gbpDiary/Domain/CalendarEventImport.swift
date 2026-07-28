import Foundation

// Pure, platform-neutral logic for importing a macOS Calendar event into a new meeting.
//
// This layer deliberately imports only Foundation — no EventKit, no SwiftData — so it is
// fully unit-testable and free of side effects. `CalendarService` (macOS-only) is responsible
// for turning `EKEvent`s into the `CalendarEventDraft` snapshots consumed here.

/// A platform-neutral snapshot of a calendar event, decoupled from `EKEvent` for testability.
struct CalendarEventDraft: Identifiable, Equatable {
    let id: String                      // EKEvent.eventIdentifier, or a synthesized fallback
    var title: String                   // "" when the event had no title
    var start: Date
    var end: Date
    var attendees: [CalendarAttendee]
    var organizerEmail: String?         // lowercased; nil when the event has no organizer
    var isAllDay: Bool
}

/// A single attendee snapshot. `email` is lowercased when present.
struct CalendarAttendee: Equatable {
    var name: String                    // display name; may fall back to the email local-part
    var email: String?
}

/// The meeting fields derived from an event, ready to seed a `Minutes` (no SwiftData here).
struct MinutesDraft: Equatable {
    var summary: String?                // nil when the event title is blank/whitespace
    var meetingAt: Date
    var duration: Duration?             // nil for all-day or zero/negative-length events
}

/// An opaque snapshot of an existing `Person`, passed into the attendee matcher.
struct PersonRef: Equatable {
    var id: UUID
    var name: String
    var email: String?
}

/// The outcome of matching one event attendee against existing People.
enum AttendeeResolution: Equatable {
    case matched(existingId: UUID)          // reuse this existing Person
    case create(name: String, email: String?)  // no match — create a new Person
}

enum CalendarEventImport {
    /// Maps an event to its meeting fields: title→summary (trimmed, nil if blank),
    /// start→meetingAt (used verbatim — the calendar time is authoritative, not quarter-hour
    /// rounded), and (end−start)→duration in hours (nil for all-day or zero/negative length).
    static func minutesDraft(from event: CalendarEventDraft) -> MinutesDraft {
        let trimmedTitle = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = trimmedTitle.isEmpty ? nil : trimmedTitle
        // All-day events carry no meeting duration (the user sets it); otherwise use end−start.
        let duration: Duration? = event.isAllDay
            ? nil
            : durationHours(start: event.start, end: event.end).map { Duration(value: $0, unit: .h) }
        return MinutesDraft(summary: summary, meetingAt: event.start, duration: duration)
    }

    /// Hours between start and end, rounded to 2 decimals to avoid floating-point dust.
    /// Returns nil when the span is zero or negative.
    static func durationHours(start: Date, end: Date) -> Double? {
        let seconds = end.timeIntervalSince(start)
        guard seconds > 0 else { return nil }
        let hours = seconds / 3600.0
        return (hours * 100).rounded() / 100
    }
}

enum AttendeeMatcher {
    /// Resolves each event attendee to an existing Person or a create-intent.
    ///
    /// Precedence per attendee: match by email (case-insensitive) first, then by exact name
    /// (case-insensitive, trimmed); otherwise `.create`. Attendees whose email is in
    /// `excludingEmails` are dropped first. Attendees with a blank name and no email are
    /// skipped. Duplicate attendees (same email, or same name when no email) collapse to one.
    static func resolve(attendees: [CalendarAttendee],
                        against people: [PersonRef],
                        excludingEmails: Set<String> = []) -> [AttendeeResolution] {
        let excluded = Set(excludingEmails.map { $0.lowercased() })
        var results: [AttendeeResolution] = []
        var seenEmails = Set<String>()
        var seenNames = Set<String>()

        for attendee in attendees {
            let email = attendee.email?.lowercased()
            if let email, excluded.contains(email) { continue }

            let name = attendee.name.trimmingCharacters(in: .whitespacesAndNewlines)
            // Skip entries with nothing usable to identify or create a Person from.
            if name.isEmpty && (email?.isEmpty ?? true) { continue }

            // Collapse duplicates within this event.
            if let email, !email.isEmpty {
                if !seenEmails.insert(email).inserted { continue }
            } else if !seenNames.insert(name.lowercased()).inserted {
                continue
            }

            if let email, !email.isEmpty,
               let match = people.first(where: { $0.email?.lowercased() == email }) {
                results.append(.matched(existingId: match.id))
            } else if !name.isEmpty,
                      let match = people.first(where: {
                          $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == name.lowercased()
                      }) {
                results.append(.matched(existingId: match.id))
            } else {
                let createEmail = (email?.isEmpty ?? true) ? nil : email
                let createName = name.isEmpty ? (createEmail ?? "") : name
                results.append(.create(name: createName, email: createEmail))
            }
        }
        return results
    }
}
