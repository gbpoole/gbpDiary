import Foundation
import Testing
@testable import gbpDiary

// A meeting belongs to the day its own `meetingAt` says, and re-dating it moves it. The bug this replaces:
// a meeting added while viewing Tuesday was stamped `now` (Thursday) but filed under Tuesday, and editing
// the date afterwards could never move it, because membership was the stored `DayEntry`.
struct DayMeetingFilteringTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return c
    }()
    // 2026-10-05 Mon … 2026-10-08 Thu, 2026-10-10 Sat.
    private func at(_ day: Int, _ hour: Int = 10, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }
    private struct Meeting { let name: String; let at: Date }
    private func meetings(on day: Int, _ all: [Meeting]) -> [String] {
        DayMeetingFiltering.meetings(on: at(day), from: all, meetingAt: \.at, calendar: cal).map(\.name)
    }

    @Test func aMeetingAppearsOnTheDayItSaysItIsOn() {
        let all = [Meeting(name: "tuesday", at: at(6, 14)), Meeting(name: "thursday", at: at(8, 10, 30))]
        #expect(meetings(on: 6, all) == ["tuesday"])
        #expect(meetings(on: 8, all) == ["thursday"])
    }

    // The reported bug, as a rule: the meeting is dated Thursday, so Tuesday must not show it — whatever
    // any stored day anchor used to say.
    @Test func aThursdayMeetingIsNotOnTuesday() {
        let all = [Meeting(name: "colloquium", at: at(8, 10, 30)), Meeting(name: "kickoff", at: at(8, 11))]
        #expect(meetings(on: 6, all).isEmpty)
        #expect(meetings(on: 8, all) == ["colloquium", "kickoff"])
    }

    // Re-dating MOVES it: the same meeting, one date change, lands on the other day with no other edit.
    @Test func reDatingMovesTheMeetingBetweenDays() {
        let before = [Meeting(name: "m", at: at(6, 11))]
        #expect(meetings(on: 6, before) == ["m"])
        #expect(meetings(on: 8, before).isEmpty)
        let after = [Meeting(name: "m", at: at(8, 11))]
        #expect(meetings(on: 6, after).isEmpty)
        #expect(meetings(on: 8, after) == ["m"])
    }

    @Test func orderedByStartTime() {
        let all = [Meeting(name: "late", at: at(8, 15)), Meeting(name: "early", at: at(8, 9)),
                   Meeting(name: "mid", at: at(8, 11, 30))]
        #expect(meetings(on: 8, all) == ["early", "mid", "late"])
    }

    // Weekend work folds back into Friday, as it does for every other logged activity — so a Saturday
    // meeting shows on Friday, and never on the following Monday.
    @Test func aWeekendMeetingFoldsBackIntoFriday() {
        let all = [Meeting(name: "saturday", at: at(10, 11))]
        #expect(meetings(on: 9, all) == ["saturday"])    // Friday 9 Oct
        #expect(meetings(on: 12, all).isEmpty)           // Monday 12 Oct
    }

    @Test func emptyInput_isEmpty() {
        #expect(meetings(on: 8, []).isEmpty)
    }
}
