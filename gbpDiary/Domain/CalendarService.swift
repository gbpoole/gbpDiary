#if os(macOS)
import EventKit
import Foundation

// macOS Calendar access, confined to this file so EventKit never leaks into the pure
// import logic (`CalendarEventImport`) or the rest of the app. Reads events across every
// calendar the user has in the macOS Calendar app — which already aggregates Exchange and
// Gmail/CalDAV accounts registered on the Mac.
//
// NOTE: `Swift.Task` does not compile in this module (a `@Model final class Task` shadows it),
// so authorization uses the completion-handler API rather than async/await; event fetching is
// synchronous and main-actor safe.

enum CalendarAccess: Equatable {
    case notDetermined
    case authorized     // full access — can read events
    case denied
    case restricted
    case writeOnly      // cannot read events; treated as "no access" by the UI
}

@MainActor
final class CalendarService {
    private let store = EKEventStore()

    /// Current authorization for reading calendar events.
    var access: CalendarAccess {
        Self.map(EKEventStore.authorizationStatus(for: .event))
    }

    /// All of the user's event calendars (id + title), sorted by title. For the Settings picker.
    func calendars() -> [CalendarInfo] {
        store.calendars(for: .event)
            .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Requests full calendar access. The completion is delivered on the main actor.
    func requestAccess(_ completion: @escaping (CalendarAccess) -> Void) {
        store.requestFullAccessToEvents { _, _ in
            // Read the resolved status rather than trusting `granted`, then hop to the main actor.
            let status = Self.map(EKEventStore.authorizationStatus(for: .event))
            DispatchQueue.main.async { completion(status) }
        }
    }

    /// All events on `day` across every calendar, mapped to platform-neutral drafts and
    /// sorted by start. Only meaningful when `access == .authorized`. The picker applies its
    /// own per-calendar filtering and proximity ordering on top of this.
    func events(on day: Date, calendar: Calendar = .current) -> [CalendarEventDraft] {
        events(around: day, daysBefore: 0, daysAfter: 0, calendar: calendar)
    }

    /// Events across a window of days centred on `day` (see `CalendarEventImport.importWindow`),
    /// so the import picker can surface an event from a nearby day — including recurring events,
    /// whose occurrences EventKit expands within the queried range.
    func events(around day: Date, daysBefore: Int, daysAfter: Int,
                calendar: Calendar = .current) -> [CalendarEventDraft] {
        guard let window = CalendarEventImport.importWindow(around: day, daysBefore: daysBefore,
                                                            daysAfter: daysAfter, calendar: calendar) else { return [] }
        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: nil)
        return store.events(matching: predicate)
            .map(Self.draft(from:))
            .sorted { $0.start < $1.start }
    }

    // MARK: - Mapping

    private nonisolated static func map(_ status: EKAuthorizationStatus) -> CalendarAccess {
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted:    return .restricted
        case .denied:        return .denied
        case .fullAccess:    return .authorized
        case .writeOnly:     return .writeOnly
        @unknown default:    return .denied
        }
    }

    private nonisolated static func draft(from event: EKEvent) -> CalendarEventDraft {
        let attendees: [CalendarAttendee] = (event.attendees ?? []).map { participant in
            let email = Self.email(from: participant.url)
            // Prefer the invite's display name; otherwise derive a human name from the email.
            let provided = participant.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = (provided?.isEmpty == false ? provided : nil)
                ?? email.map(CalendarEventImport.displayName(fromEmail:))
                ?? ""
            return CalendarAttendee(name: name, email: email)
        }
        return CalendarEventDraft(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            attendees: attendees,
            organizerEmail: Self.email(from: event.organizer?.url),
            isAllDay: event.isAllDay,
            calendarId: event.calendar?.calendarIdentifier ?? "",
            calendarTitle: event.calendar?.title ?? ""
        )
    }

    /// Attendee/organizer URLs are `mailto:` links; extract and lowercase the address.
    private nonisolated static func email(from url: URL?) -> String? {
        guard let url else { return nil }
        let s = url.absoluteString
        let addr = s.hasPrefix("mailto:") ? String(s.dropFirst("mailto:".count)) : s
        let trimmed = addr.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }
}
#endif
