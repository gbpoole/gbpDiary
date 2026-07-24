import Foundation
import Testing
@testable import gbpDiary

@MainActor
struct ValueTypesTests {

    // MARK: - DaySlot.displayName

    @Test func daySlot_displayNames() {
        #expect(DaySlot.allDay.displayName == "All Day")
        #expect(DaySlot.morning.displayName == "Morning")
        #expect(DaySlot.afternoon.displayName == "Afternoon")
    }

    // MARK: - DaySlot.defaultDuration

    @Test func daySlot_defaultDuration_allDay_isOneDay() {
        let dur = DaySlot.allDay.defaultDuration
        #expect(dur.value == 1.0)
        #expect(dur.unit == .d)
        #expect(dur.hoursNormalized == 7.6)
    }

    @Test func daySlot_defaultDuration_morning_isHalfDay() {
        let dur = DaySlot.morning.defaultDuration
        #expect(dur.value == 0.5)
        #expect(dur.unit == .d)
        #expect(dur.hoursNormalized == 3.8)
    }

    @Test func daySlot_defaultDuration_afternoon_isHalfDay() {
        let dur = DaySlot.afternoon.defaultDuration
        #expect(dur.value == 0.5)
        #expect(dur.unit == .d)
        #expect(dur.hoursNormalized == 3.8)
    }
}
