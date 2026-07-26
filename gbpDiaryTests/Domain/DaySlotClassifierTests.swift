import Testing
import Foundation
@testable import gbpDiary

@Suite("DaySlotClassifier")
struct DaySlotClassifierTests {
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private func time(_ hour: Int, _ minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = 2024; comps.month = 1; comps.day = 15
        comps.hour = hour; comps.minute = minute; comps.second = 0
        return calendar.date(from: comps)!
    }

    @Test func before1230_isMorning() {
        #expect(DaySlotClassifier.slot(for: time(9), eveningStart: nil, calendar: calendar) == .morning)
        #expect(DaySlotClassifier.slot(for: time(12, 29), eveningStart: nil, calendar: calendar) == .morning)
    }

    @Test func atOrAfter1230_isAfternoon() {
        #expect(DaySlotClassifier.slot(for: time(12, 30), eveningStart: nil, calendar: calendar) == .afternoon)
        #expect(DaySlotClassifier.slot(for: time(17), eveningStart: nil, calendar: calendar) == .afternoon)
    }

    @Test func withoutEveningBlock_lateTimeStaysAfternoon() {
        // No evening block → nothing classifies as evening, even at 21:00.
        #expect(DaySlotClassifier.slot(for: time(21), eveningStart: nil, calendar: calendar) == .afternoon)
    }

    @Test func withEveningBlock_afterStartIsEvening() {
        let eveningStart = time(18)
        #expect(DaySlotClassifier.slot(for: time(18), eveningStart: eveningStart, calendar: calendar) == .evening)
        #expect(DaySlotClassifier.slot(for: time(20), eveningStart: eveningStart, calendar: calendar) == .evening)
        // Before the evening start it's still afternoon.
        #expect(DaySlotClassifier.slot(for: time(17, 59), eveningStart: eveningStart, calendar: calendar) == .afternoon)
    }

    @Test func flexibleEveningStart_isRespected() {
        let eveningStart = time(16)   // an early evening block
        #expect(DaySlotClassifier.slot(for: time(16), eveningStart: eveningStart, calendar: calendar) == .evening)
        #expect(DaySlotClassifier.slot(for: time(15, 59), eveningStart: eveningStart, calendar: calendar) == .afternoon)
    }

    @Test func daySlot_evening_hasNoStandardCapacity_andIsOvertime() {
        #expect(DaySlot.evening.defaultDuration.hoursNormalized == 0)
        #expect(DaySlot.evening.isOvertime)
        #expect(!DaySlot.morning.isOvertime)
    }
}
