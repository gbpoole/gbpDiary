import Foundation
import Testing
@testable import gbpDiary

struct ChatWeekendFoldTests {
    // 2024-01-06 is a Saturday, 01-07 Sunday, 01-05 Friday, 01-08 Monday.
    private let cal = Calendar(identifier: .gregorian)
    private func d(_ day: Int) -> Date { cal.date(from: DateComponents(year: 2024, month: 1, day: day))! }

    @Test func meetingFoldsWeekendBackToFriday() {
        #expect(ChatWeekendFold.fold(d(6), kind: .meeting, calendar: cal) == d(5))  // Sat → Fri (work)
        #expect(ChatWeekendFold.fold(d(7), kind: .meeting, calendar: cal) == d(5))  // Sun → Fri
    }

    @Test func emailAndTaskFoldWeekendForwardToMonday() {
        #expect(ChatWeekendFold.fold(d(6), kind: .email, calendar: cal) == d(8))   // Sat → Mon (inbound)
        #expect(ChatWeekendFold.fold(d(7), kind: .task, calendar: cal) == d(8))    // Sun → Mon
    }

    @Test func weekdayIsUnchanged() {
        #expect(ChatWeekendFold.fold(d(3), kind: .meeting, calendar: cal) == d(3)) // Wed → Wed
        #expect(ChatWeekendFold.fold(d(5), kind: .email, calendar: cal) == d(5))   // Fri → Fri
    }

    @Test func foldWork_alwaysBackToFriday() {
        #expect(ChatWeekendFold.foldWork(d(6), calendar: cal) == d(5))
        #expect(ChatWeekendFold.foldWork(d(8), calendar: cal) == d(8))
    }
}
