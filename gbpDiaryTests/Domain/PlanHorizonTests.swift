import Foundation
import Testing
@testable import gbpDiary

struct PlanHorizonTests {
    @Test func rank_ordersTodayThisWeekMaybe() {
        #expect(PlanHorizon.today.rank < PlanHorizon.thisWeek.rank)
        #expect(PlanHorizon.thisWeek.rank < PlanHorizon.maybe.rank)
    }

    @Test func displayName_isHumanReadable() {
        #expect(PlanHorizon.today.displayName == "Today")
        #expect(PlanHorizon.thisWeek.displayName == "This Week")
        #expect(PlanHorizon.maybe.displayName == "Maybe")
    }

    @Test func rawValue_roundTrips() {
        for h in PlanHorizon.allCases {
            #expect(PlanHorizon(rawValue: h.rawValue) == h)
        }
    }
}
