import Testing
import Foundation
@testable import gbpDiary

@Suite("MeetingSlotHours")
struct MeetingSlotHoursTests {
    private let cal = Calendar.current
    private func at(_ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2024, month: 1, day: 3, hour: h, minute: m))!
    }
    private func overlap(_ start: Date, _ hours: Double, _ slot: DaySlot) -> Double {
        MeetingSlotHours.overlapHours(start: start, durationHours: hours, slot: slot, on: start, calendar: cal)
    }

    @Test func meetingEndingExactlyAt1230_isAllMorningNoAfternoon() {
        // The reported case: 11:30–12:30 (boundary is 12:30) → wholly morning.
        #expect(overlap(at(11, 30), 1, .morning) == 1.0)
        #expect(overlap(at(11, 30), 1, .afternoon) == 0.0)
    }

    @Test func meetingStraddling1230_splitsInHalf() {
        #expect(overlap(at(12, 0), 1, .morning) == 0.5)
        #expect(overlap(at(12, 0), 1, .afternoon) == 0.5)
    }

    @Test func whollyAfternoonMeeting() {
        #expect(overlap(at(14, 0), 1, .morning) == 0.0)
        #expect(overlap(at(14, 0), 1, .afternoon) == 1.0)
    }

    @Test func allDayIsNeverSplit() {
        #expect(overlap(at(11, 30), 1, .allDay) == 1.0)
        #expect(overlap(at(12, 0), 1.5, .allDay) == 1.5)
    }

    @Test func zeroDuration_isZero() {
        #expect(overlap(at(12, 0), 0, .morning) == 0.0)
    }
}
