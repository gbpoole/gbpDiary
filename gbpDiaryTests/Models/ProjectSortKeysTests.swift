import Foundation
import SwiftData
import Testing
@testable import gbpDiary

@MainActor
struct ProjectSortKeysTests {
    @Test func streamKey_lowercasesAndDefaultsEmpty() {
        let p = Project(name: "P")
        #expect(p.streamKey == "")
        p.stream = "Cosmology"
        #expect(p.streamKey == "cosmology")
    }

    @Test func nameKey_isLowercased() {
        #expect(Project(name: "Zeta").nameKey == "zeta")
    }

    @Test func subprojectCount_countsChildren() {
        let parent = Project(name: "Parent")
        parent.subprojects = [Project(name: "a"), Project(name: "b")]
        #expect(parent.subprojectCount == 2)
    }

    @Test func lastMeetingAt_isLatestOrDistantPast() {
        let p = Project(name: "P")
        #expect(p.lastMeetingAt == .distantPast)   // no meetings
        let early = Minutes(meetingAt: FixedDates.reference)
        let late = Minutes(meetingAt: FixedDates.reference.addingTimeInterval(3600))
        p.meetings = [early, late]
        #expect(p.lastMeetingAt == late.meetingAt)
    }

    @Test func teamNames_leadFirstThenAlphabetical() {
        let lead = Person(name: "Zoe")
        let a = Person(name: "Amy")
        let m = Person(name: "Mike")
        let names = Project.teamNames(lead: lead, team: [m, a, lead])
        #expect(names == ["Zoe", "Amy", "Mike"])   // lead first, others sorted, lead not duplicated
    }

    @Test func teamKey_isLowercasedJoinOfTeamNames() {
        let lead = Person(name: "Zoe")
        let a = Person(name: "Amy")
        #expect(Project.teamKey(lead: lead, team: [a]) == "zoe, amy")
    }
}
