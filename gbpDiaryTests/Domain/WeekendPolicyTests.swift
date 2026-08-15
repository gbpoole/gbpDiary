import Foundation
import Testing
@testable import gbpDiary

struct WeekendPolicyTests {
    // 2024-01-01 is a Monday. Mon 01 · Tue 02 · Wed 03 · Thu 04 · Fri 05 · Sat 06 · Sun 07 · Mon 08.
    private let cal = Calendar(identifier: .gregorian)
    private func d(_ month: Int, _ day: Int) -> Date {
        cal.date(from: DateComponents(year: 2024, month: month, day: day))!
    }

    @Test func isWeekend_saturdaySunday() {
        #expect(WeekendPolicy.isWeekend(d(1, 6), calendar: cal))   // Sat
        #expect(WeekendPolicy.isWeekend(d(1, 7), calendar: cal))   // Sun
        #expect(!WeekendPolicy.isWeekend(d(1, 5), calendar: cal))  // Fri
        #expect(!WeekendPolicy.isWeekend(d(1, 1), calendar: cal))  // Mon
    }

    @Test func weekday_resolvesWeekendForwardToMonday() {
        #expect(WeekendPolicy.weekday(for: d(1, 6), calendar: cal) == d(1, 8))   // Sat → next Mon
        #expect(WeekendPolicy.weekday(for: d(1, 7), calendar: cal) == d(1, 8))   // Sun → next Mon
        #expect(WeekendPolicy.weekday(for: d(1, 1), calendar: cal) == d(1, 1))   // Mon → itself
        #expect(WeekendPolicy.weekday(for: d(1, 3), calendar: cal) == d(1, 3))   // Wed → itself
    }

    @Test func steppedWeekday_skipsWeekends() {
        #expect(WeekendPolicy.steppedWeekday(from: d(1, 5), delta: 1, calendar: cal) == d(1, 8))   // Fri +1 → Mon
        #expect(WeekendPolicy.steppedWeekday(from: d(1, 8), delta: -1, calendar: cal) == d(1, 5))  // Mon −1 → Fri
        #expect(WeekendPolicy.steppedWeekday(from: d(1, 3), delta: 1, calendar: cal) == d(1, 4))   // Wed +1 → Thu
        #expect(WeekendPolicy.steppedWeekday(from: d(1, 3), delta: 0, calendar: cal) == d(1, 3))   // no-op
    }

    @Test func weekdays_ofWeek_areMonToFri() {
        let days = WeekendPolicy.weekdays(ofWeekContaining: d(1, 3), calendar: cal)
        #expect(days == [d(1, 1), d(1, 2), d(1, 3), d(1, 4), d(1, 5)])
    }

    @Test func forwardRange_mondayAbsorbsPrecedingWeekend() {
        let r = WeekendPolicy.forwardRange(for: d(1, 8), calendar: cal)   // Monday
        #expect(r == d(1, 6)..<d(1, 9))          // Sat ..< Tue
        #expect(r.contains(d(1, 6)) && r.contains(d(1, 7)) && r.contains(d(1, 8)))
        #expect(!r.contains(d(1, 5)) && !r.contains(d(1, 9)))
    }

    @Test func forwardRange_plainWeekdayIsSingleDay() {
        #expect(WeekendPolicy.forwardRange(for: d(1, 2), calendar: cal) == d(1, 2)..<d(1, 3))
    }

    @Test func workRange_fridayAbsorbsFollowingWeekend() {
        let r = WeekendPolicy.workRange(for: d(1, 5), calendar: cal)   // Friday
        #expect(r == d(1, 5)..<d(1, 8))          // Fri ..< Mon
        #expect(r.contains(d(1, 5)) && r.contains(d(1, 6)) && r.contains(d(1, 7)))
        #expect(!r.contains(d(1, 8)))
    }

    @Test func workRange_plainWeekdayIsSingleDay() {
        #expect(WeekendPolicy.workRange(for: d(1, 2), calendar: cal) == d(1, 2)..<d(1, 3))
    }

    private func at(_ day: Int, _ h: Int, _ min: Int) -> Date {
        cal.date(from: DateComponents(year: 2024, month: 1, day: day, hour: h, minute: min))!
    }

    @Test func logNowDate_weekendOnGreenMonday_usesRealWeekendTime() {
        // Now = Saturday 14:07, parked on the Monday it folds into → stamp the real (rounded) Saturday time.
        let result = WeekendPolicy.logNowDate(viewedDate: d(1, 8), now: at(6, 14, 7), calendar: cal)
        #expect(cal.isDate(result, inSameDayAs: d(1, 6)))          // Saturday, not Monday
        #expect(cal.component(.minute, from: result) % 15 == 0)    // rounded to quarter-hour (14:00)
    }

    @Test func logNowDate_weekday_appliesNowTimeToViewedDay() {
        // Now = Wednesday 09:07, viewing Wednesday → 09:15 on Wednesday.
        let result = WeekendPolicy.logNowDate(viewedDate: d(1, 3), now: at(3, 9, 7), calendar: cal)
        #expect(cal.isDate(result, inSameDayAs: d(1, 3)))
        #expect(cal.component(.minute, from: result) % 15 == 0)
    }

    @Test func logNowDate_weekendButViewingAnotherDay_usesViewedDay() {
        // Now = Saturday but reviewing Friday (not the green Monday) → apply now's time to Friday.
        let result = WeekendPolicy.logNowDate(viewedDate: d(1, 5), now: at(6, 14, 7), calendar: cal)
        #expect(cal.isDate(result, inSameDayAs: d(1, 5)))          // Friday, not Saturday
    }
}
