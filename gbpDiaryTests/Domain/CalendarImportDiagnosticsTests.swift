import Foundation
import Testing
@testable import gbpDiary

/// The caption under the meeting-import picker. An empty EventKit fetch carries no error, so this line
/// is the only thing that distinguishes "no access", "nothing in these days" and "asked for the wrong
/// days" — the last being the live suspicion, since a new meeting is anchored on the VIEWED diary day.
@Suite("CalendarImportDiagnostics")
struct CalendarImportDiagnosticsTests {

    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private func day(_ d: Int, month: Int = 1) -> Date {
        calendar.date(from: DateComponents(year: 2024, month: month, day: d))!
    }

    @Test func statesAccessWhenThereIsNoWindowToReport() {
        let d = CalendarImportDiagnostics(access: "denied")
        #expect(d.summary(calendar: calendar) == "access: denied · 0 events")
    }

    /// The window's end bound is exclusive, so the line must name the last *included* day — otherwise
    /// a ±3-day window reads as four days after the anchor and the report misleads.
    @Test func namesTheLastIncludedDayNotTheExclusiveEnd() {
        let d = CalendarImportDiagnostics(access: "authorized",
                                          windows: [(start: day(12), end: day(19))],
                                          attempts: 4)
        let line = d.summary(calendar: calendar)
        #expect(line.contains("12 Jan–18 Jan"))
        #expect(!line.contains("19 Jan"))
        #expect(line.contains("0 events"))
        #expect(line.contains("4 attempts"))
    }

    @Test func reportsBothWindowsWhenTodayWasAddedSeparately() {
        let d = CalendarImportDiagnostics(access: "authorized",
                                          windows: [(start: day(12), end: day(19)),
                                                    (start: day(28), end: day(4, month: 2))])
        let line = d.summary(calendar: calendar)
        #expect(line.contains("12 Jan–18 Jan + 28 Jan–3 Feb"))
    }

    /// Calendars are only worth reporting when something was found — "0 events · 0 calendars" reads as
    /// a second failure rather than a consequence of the first.
    @Test func mentionsCalendarsOnlyWhenEventsWereFound() {
        let empty = CalendarImportDiagnostics(access: "authorized", calendarsWithEvents: 0, eventsFound: 0)
        #expect(!empty.summary(calendar: calendar).contains("calendar"))

        let found = CalendarImportDiagnostics(access: "authorized", calendarsWithEvents: 3, eventsFound: 7)
        let line = found.summary(calendar: calendar)
        #expect(line.contains("7 events"))
        #expect(line.contains("3 calendars"))
    }

    @Test func singularsReadCorrectly() {
        let d = CalendarImportDiagnostics(access: "authorized", calendarsWithEvents: 1,
                                          eventsFound: 1, attempts: 1)
        let line = d.summary(calendar: calendar)
        #expect(line.contains("1 event ") || line.hasSuffix("1 event"))
        #expect(line.contains("1 calendar ") || line.contains("1 calendar ·"))
        #expect(line.contains("1 attempt"))
        #expect(!line.contains("1 events"))
        #expect(!line.contains("1 attempts"))
    }

    /// Retry must actually re-run the load task, which only happens if the key differs.
    @Test func loadKeyChangesWithTheAnchorAndWithRetry() {
        let base = CalendarLoadKey(anchor: day(15), attempt: 0)
        #expect(base == CalendarLoadKey(anchor: day(15), attempt: 0))
        #expect(base != CalendarLoadKey(anchor: day(15), attempt: 1))
        #expect(base != CalendarLoadKey(anchor: day(16), attempt: 0))
    }
}
