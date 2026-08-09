import Testing
import Foundation
@testable import gbpDiary

@Suite("DateWindow")
struct DateWindowTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()
    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 15) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    @Test func ranges_startAndEnd() {
        let now = at(2026, 8, 9, 15)
        let startOfToday = at(2026, 8, 9, 0)
        #expect(DateWindow.today.range(now: now, calendar: cal) == startOfToday...now)
        #expect(DateWindow.week.range(now: now, calendar: cal) == at(2026, 8, 3, 0)...now)   // 6 days before
        #expect(DateWindow.month.range(now: now, calendar: cal) == at(2026, 7, 11, 0)...now) // 29 days before
    }
}
