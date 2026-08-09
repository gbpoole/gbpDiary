import Testing
import Foundation
@testable import gbpDiary

@Suite("Recurrence & wait")
struct RecurrenceTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()
    private func at(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @Test func parse_variants() {
        #expect(RecurrenceRule.parse("1w") == RecurrenceRule(count: 1, unit: .week))
        #expect(RecurrenceRule.parse("2mo") == RecurrenceRule(count: 2, unit: .month))
        #expect(RecurrenceRule.parse("3d") == RecurrenceRule(count: 3, unit: .day))
        #expect(RecurrenceRule.parse("y") == RecurrenceRule(count: 1, unit: .year))   // bare unit → 1
        #expect(RecurrenceRule.parse("") == nil)
        #expect(RecurrenceRule.parse("5x") == nil)
        #expect(RecurrenceRule.parse("0w") == nil)
    }

    @Test func next_advancesByUnit() {
        #expect(RecurrenceRule(count: 1, unit: .week).next(after: at(2026, 8, 9), calendar: cal) == at(2026, 8, 16))
        #expect(RecurrenceRule(count: 3, unit: .day).next(after: at(2026, 8, 9), calendar: cal) == at(2026, 8, 12))
        #expect(RecurrenceRule(count: 2, unit: .month).next(after: at(2026, 8, 9), calendar: cal) == at(2026, 10, 9))
        #expect(RecurrenceRule(count: 1, unit: .year).next(after: at(2026, 8, 9), calendar: cal) == at(2027, 8, 9))
    }

    @Test func isWaiting_futureOnly() {
        let now = at(2026, 8, 9)
        #expect(TaskFlags.isWaiting(waitUntil: at(2026, 8, 15), now: now))
        #expect(!TaskFlags.isWaiting(waitUntil: at(2026, 8, 1), now: now))
        #expect(!TaskFlags.isWaiting(waitUntil: nil, now: now))
    }
}
