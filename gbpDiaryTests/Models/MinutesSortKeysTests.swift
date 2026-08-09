import Foundation
import SwiftData
import Testing
@testable import gbpDiary

@MainActor
struct MinutesSortKeysTests {
    @Test func summaryKey_isLowercasedOrEmpty() {
        let m = Minutes(meetingAt: FixedDates.reference)
        #expect(m.summaryKey == "")   // nil summary
        m.summary = "Weekly Sync"
        #expect(m.summaryKey == "weekly sync")
    }

    @Test func projectsKey_isSortedLowercasedJoin() {
        let m = Minutes(meetingAt: FixedDates.reference)
        #expect(m.projectsKey == "")   // no projects
        m.projects = [Project(name: "Zeta"), Project(name: "Alpha")]
        #expect(m.projectsKey == "alpha, zeta")   // sorted then lowercased
    }

    @Test func attendeeCount_countsAttendees() {
        let m = Minutes(meetingAt: FixedDates.reference)
        #expect(m.attendeeCount == 0)
        m.attendees = [Person(name: "a"), Person(name: "b"), Person(name: "c")]
        #expect(m.attendeeCount == 3)
    }
}
