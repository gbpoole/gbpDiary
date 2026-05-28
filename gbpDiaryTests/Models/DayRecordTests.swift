import Foundation
import Testing
@testable import gbpDiary

@MainActor
struct DayRecordTests {
    @Test func init_normalizesDateToStartOfDay() {
        let calendar = Calendar.current
        let raw = FixedDates.atHour(15)
        let record = DayRecord(date: raw)
        #expect(record.date == calendar.startOfDay(for: raw))
    }

    @Test func focusTags_roundTripViaJsonStorage() {
        let record = DayRecord(date: FixedDates.reference)
        record.focusTags = ["deep-work", "planning"]
        #expect(record.focusTags == ["deep-work", "planning"])
    }
}
