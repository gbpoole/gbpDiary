import Testing
import Foundation
@testable import gbpDiary

@Suite("MeetingSlotClassifier")
struct MeetingSlotTests {
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private func date(hour: Int, minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = 2024; comps.month = 1; comps.day = 15
        comps.hour = hour; comps.minute = minute; comps.second = 0
        return calendar.date(from: comps)!
    }

    private var referenceDay: Date { date(hour: 9) }

    private func minutes(startHour: Int, startMinute: Int = 0, durationHours: Double? = nil) -> Minutes {
        let m = Minutes(meetingAt: date(hour: startHour, minute: startMinute))
        if let h = durationHours {
            m.duration = Duration(value: h, unit: .h)
        }
        return m
    }

    @Test func slots_morningOnly_noDuration() {
        let m = minutes(startHour: 9)
        let result = MeetingSlotClassifier.slots(for: m, on: referenceDay, calendar: calendar)
        #expect(result == [.morning])
    }

    @Test func slots_afternoonOnly_noduration() {
        let m = minutes(startHour: 14)
        let result = MeetingSlotClassifier.slots(for: m, on: referenceDay, calendar: calendar)
        #expect(result == [.afternoon])
    }

    @Test func slots_spansNoon_morningStartLongDuration() {
        let m = minutes(startHour: 11, durationHours: 2.0)
        let result = MeetingSlotClassifier.slots(for: m, on: referenceDay, calendar: calendar)
        #expect(result == [.morning, .afternoon])
    }

    @Test func slots_morningOnly_shortDurationEndsBeforeNoon() {
        let m = minutes(startHour: 11, startMinute: 0, durationHours: 0.5)
        let result = MeetingSlotClassifier.slots(for: m, on: referenceDay, calendar: calendar)
        #expect(result == [.morning])
    }

    @Test func slots_before1230_isMorning() {
        let m = minutes(startHour: 12, startMinute: 0)
        let result = MeetingSlotClassifier.slots(for: m, on: referenceDay, calendar: calendar)
        #expect(result == [.morning])
    }

    @Test func slots_exactlyAt1230_isAfternoon() {
        let m = minutes(startHour: 12, startMinute: 30)
        let result = MeetingSlotClassifier.slots(for: m, on: referenceDay, calendar: calendar)
        #expect(result == [.afternoon])
    }

    @Test func slots_endsExactlyAt1230_spansBoundary() {
        // 12:29 + 1 min = 12:30 → end >= boundary
        let m = minutes(startHour: 12, startMinute: 29, durationHours: 1.0 / 60.0)
        let result = MeetingSlotClassifier.slots(for: m, on: referenceDay, calendar: calendar)
        #expect(result == [.morning, .afternoon])
    }
}
