import Testing
import Foundation
@testable import gbpDiary

@Suite("CalendarEventImport")
@MainActor
struct CalendarEventImportTests {
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private func date(hour: Int, minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = 2024; comps.month = 1; comps.day = 15
        comps.hour = hour; comps.minute = minute
        return calendar.date(from: comps)!
    }

    private func event(title: String, start: Date, end: Date,
                       isAllDay: Bool = false,
                       attendees: [CalendarAttendee] = []) -> CalendarEventDraft {
        CalendarEventDraft(id: "e1", title: title, start: start, end: end,
                           attendees: attendees, organizerEmail: nil, isAllDay: isAllDay)
    }

    @Test func minutesDraft_mapsTitleToSummary_trimmed() {
        let e = event(title: "  Standup  ", start: date(hour: 9), end: date(hour: 10))
        #expect(CalendarEventImport.minutesDraft(from: e).summary == "Standup")
    }

    @Test func minutesDraft_blankTitle_yieldsNilSummary() {
        let e = event(title: "   ", start: date(hour: 9), end: date(hour: 10))
        #expect(CalendarEventImport.minutesDraft(from: e).summary == nil)
    }

    @Test func durationHours_computesEndMinusStart() {
        #expect(CalendarEventImport.durationHours(start: date(hour: 9), end: date(hour: 10, minute: 30)) == 1.5)
    }

    @Test func durationHours_zeroOrNegative_yieldsNil() {
        #expect(CalendarEventImport.durationHours(start: date(hour: 9), end: date(hour: 9)) == nil)
        #expect(CalendarEventImport.durationHours(start: date(hour: 10), end: date(hour: 9)) == nil)
    }

    @Test func durationHours_roundedToTwoDecimals() {
        // 20 minutes = 0.3333… hours → rounded to 0.33
        #expect(CalendarEventImport.durationHours(start: date(hour: 9), end: date(hour: 9, minute: 20)) == 0.33)
    }

    @Test func minutesDraft_timedEvent_setsDurationInHours() {
        let e = event(title: "Sync", start: date(hour: 9), end: date(hour: 10, minute: 30))
        let d = CalendarEventImport.minutesDraft(from: e).duration
        #expect(d == Duration(value: 1.5, unit: .h))
    }

    @Test func minutesDraft_allDayEvent_yieldsNilDuration() {
        let e = event(title: "Conference", start: date(hour: 0), end: date(hour: 23, minute: 59), isAllDay: true)
        #expect(CalendarEventImport.minutesDraft(from: e).duration == nil)
    }

    @Test func minutesDraft_meetingAtEqualsStart_notRounded() {
        let start = date(hour: 9, minute: 7)   // deliberately off a quarter-hour boundary
        let e = event(title: "Sync", start: start, end: date(hour: 10))
        #expect(CalendarEventImport.minutesDraft(from: e).meetingAt == start)
    }

    @Test func sortedByProximity_ordersByDistanceFromReference() {
        let now = date(hour: 12)
        let near = event(title: "near", start: date(hour: 12, minute: 30), end: date(hour: 13)) // 30m away
        let far = event(title: "far", start: date(hour: 9), end: date(hour: 10))                 // 3h away
        let mid = event(title: "mid", start: date(hour: 13, minute: 30), end: date(hour: 14))    // 1.5h away
        let sorted = CalendarEventImport.sortedByProximity([far, mid, near], to: now)
        #expect(sorted.map(\.title) == ["near", "mid", "far"])
    }

    @Test func displayName_fromDottedLocalPart_capitalisesWords() {
        #expect(CalendarEventImport.displayName(fromEmail: "john.smith@example.com") == "John Smith")
    }

    @Test func displayName_lowercasesRestAndCapitalisesFirst() {
        #expect(CalendarEventImport.displayName(fromEmail: "JOHN.SMITH@x.com") == "John Smith")
    }

    @Test func displayName_singleWord() {
        #expect(CalendarEventImport.displayName(fromEmail: "jsmith@x.com") == "Jsmith")
    }

    @Test func displayName_handlesUnderscoreHyphenPlus() {
        #expect(CalendarEventImport.displayName(fromEmail: "mary-jane_watson+cal@x.com") == "Mary Jane Watson Cal")
    }

    @Test func displayName_noDomain() {
        #expect(CalendarEventImport.displayName(fromEmail: "bob") == "Bob")
    }

    @Test func sortedByProximity_treatsPastAndFutureByAbsoluteDistance() {
        let now = date(hour: 12)
        let past = event(title: "past", start: date(hour: 11), end: date(hour: 11, minute: 30))  // 1h before
        let future = event(title: "future", start: date(hour: 14), end: date(hour: 15))          // 2h after
        let sorted = CalendarEventImport.sortedByProximity([future, past], to: now)
        #expect(sorted.map(\.title) == ["past", "future"])
    }
}
