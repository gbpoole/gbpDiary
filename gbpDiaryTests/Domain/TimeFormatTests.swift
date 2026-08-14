import Foundation
import Testing
@testable import gbpDiary

struct TimeFormatTests {
    @Test func short_zero_isZeroMinutes() {
        #expect(TimeFormat.short(hours: 0) == "0m")
    }

    @Test func short_tinyValue_roundsUpToOneMinute() {
        #expect(TimeFormat.short(hours: 1.0 / 60.0 / 4.0) == "1m")   // ~15s → 1m, never "0m"
    }

    @Test func short_minutesUnderAnHour() {
        #expect(TimeFormat.short(hours: 1.0 / 60.0) == "1m")
        #expect(TimeFormat.short(hours: 5.0 / 60.0) == "5m")
        #expect(TimeFormat.short(hours: 15.0 / 60.0) == "15m")
        #expect(TimeFormat.short(hours: 45.0 / 60.0) == "45m")
    }

    @Test func short_wholeHours() {
        #expect(TimeFormat.short(hours: 1.0) == "1h")
        #expect(TimeFormat.short(hours: 2.0) == "2h")
    }

    @Test func short_mixedHoursAndMinutes() {
        #expect(TimeFormat.short(hours: 65.0 / 60.0) == "1h 5m")
        #expect(TimeFormat.short(hours: 1.5) == "1h 30m")
    }
}
