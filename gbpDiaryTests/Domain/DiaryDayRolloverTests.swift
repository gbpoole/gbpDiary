import Testing
import Foundation
@testable import gbpDiary

@Suite("DiaryDayRollover")
struct DiaryDayRolloverTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Australia/Melbourne")!
        return c
    }()

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test func tracksToday_pastDay_rollsForwardToToday() {
        let result = DiaryDayRollover.rolledForwardDate(
            currentDate: at(2026, 7, 29, 0, 0), tracksToday: true,
            now: at(2026, 7, 30, 8, 6), calendar: cal)
        #expect(result == at(2026, 7, 30, 0, 0))
    }

    @Test func tracksToday_sameDay_staysPut() {
        let result = DiaryDayRollover.rolledForwardDate(
            currentDate: at(2026, 7, 30, 0, 0), tracksToday: true,
            now: at(2026, 7, 30, 23, 59), calendar: cal)
        #expect(result == nil)
    }

    @Test func notTracking_pastDay_staysPut() {
        // The user deliberately navigated to a past day — never auto-advance.
        let result = DiaryDayRollover.rolledForwardDate(
            currentDate: at(2026, 7, 29, 0, 0), tracksToday: false,
            now: at(2026, 7, 30, 8, 6), calendar: cal)
        #expect(result == nil)
    }

    @Test func tracksToday_futureDay_staysPut() {
        let result = DiaryDayRollover.rolledForwardDate(
            currentDate: at(2026, 7, 31, 0, 0), tracksToday: true,
            now: at(2026, 7, 30, 8, 6), calendar: cal)
        #expect(result == nil)
    }
}
