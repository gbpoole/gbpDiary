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
    /// One store for the whole app. `EKEventStore` is expensive to create and loads its sources (local,
    /// CalDAV, Exchange) lazily in the background, so a freshly built store can answer the first query
    /// with nothing at all. Every view used to hold `@State private var service = CalendarService()`,
    /// which constructs a new store on every struct init and keeps whichever one happened to mount — the
    /// reason the meeting-import list came up empty at random. Views read `.shared`.
    static let shared = CalendarService()

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
        store.requestFullAccessToEvents { granted, _ in
            // Trust `granted`: right after the first approval TCC hasn't yet propagated the new value to
            // `authorizationStatus`, so re-reading it here would wrongly report `.notDetermined` and the
            // caller would never load events. Fall back to the read status only when not granted (to
            // distinguish denied/restricted/writeOnly).
            let status = Self.resolve(granted: granted,
                                      fallback: Self.map(EKEventStore.authorizationStatus(for: .event)))
            DispatchQueue.main.async { completion(status) }
        }
    }

    /// Resolves the effective access from EventKit's `granted` flag (authoritative on approval) and the
    /// status read as a fallback. Pure — no EventKit — so it is unit-testable.
    nonisolated static func resolve(granted: Bool, fallback: CalendarAccess) -> CalendarAccess {
        granted ? .authorized : fallback
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
        return events(inWindows: [window])
    }

    /// Events across one or more windows (see `CalendarEventImport.importWindows`), deduped by event id
    /// and sorted by start. `refreshingSources` asks EventKit to re-read its accounts first — worth doing
    /// on the first attempt of a fetch, since a store whose sources have not finished loading reports no
    /// events rather than an error.
    func events(inWindows windows: [(start: Date, end: Date)],
                refreshingSources refresh: Bool = false) -> [CalendarEventDraft] {
        guard !windows.isEmpty else { return [] }
        if refresh {
            // `reset()` matters now that the store is long-lived (it used to be rebuilt per view): an
            // un-reset store keeps serving its cached snapshot, and after Calendar syncs — which it does
            // constantly with Exchange/CalDAV accounts — that snapshot can answer with nothing. Every
            // result here is copied into value-type drafts immediately, so invalidating the store's own
            // objects costs nothing.
            store.reset()
            store.refreshSourcesIfNecessary()
        }
        var seen = Set<String>()
        var drafts: [CalendarEventDraft] = []
        for window in windows {
            let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: nil)
            for event in store.events(matching: predicate) {
                let draft = Self.draft(from: event)
                guard seen.insert(draft.id).inserted else { continue }
                drafts.append(draft)
            }
        }
        return drafts.sorted { $0.start < $1.start }
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
