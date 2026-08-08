import Testing
import Foundation
@testable import gbpDiary

@Suite("TaskFlags & TaskPriority")
struct TaskFlagsTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()
    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    @Test func isOverdue_pastDueAndOpen() {
        let now = at(2026, 8, 8)
        #expect(TaskFlags.isOverdue(dueAt: at(2026, 8, 7), isOpen: true, now: now, calendar: cal))
        #expect(!TaskFlags.isOverdue(dueAt: at(2026, 8, 7), isOpen: false, now: now, calendar: cal))  // done
        #expect(!TaskFlags.isOverdue(dueAt: at(2026, 8, 8), isOpen: true, now: now, calendar: cal))    // today, not overdue
        #expect(!TaskFlags.isOverdue(dueAt: nil, isOpen: true, now: now, calendar: cal))
    }

    @Test func isDueToday_sameCalendarDay() {
        let now = at(2026, 8, 8)
        #expect(TaskFlags.isDueToday(dueAt: at(2026, 8, 8, 9), now: now, calendar: cal))
        #expect(!TaskFlags.isDueToday(dueAt: at(2026, 8, 9), now: now, calendar: cal))
        #expect(!TaskFlags.isDueToday(dueAt: nil, now: now, calendar: cal))
    }

    @Test func priority_weightsAndShort() {
        #expect(TaskPriority.high.weight > TaskPriority.medium.weight)
        #expect(TaskPriority.medium.weight > TaskPriority.low.weight)
        #expect(TaskPriority.low.weight > TaskPriority.none.weight)
        #expect(TaskPriority.high.short == "H")
        #expect(TaskPriority.none.short == "")
        #expect(TaskPriority(rawValue: "medium") == .medium)
    }
}
