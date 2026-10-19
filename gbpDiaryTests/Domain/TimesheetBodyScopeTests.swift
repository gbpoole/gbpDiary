import Foundation
import Testing
@testable import gbpDiary

// Which bodies are worth an AppleScript round-trip. Measured motivation: a week of real mail held 154
// non-dismissed messages of which only 3 were timesheet-relevant, so fetching everything would spend
// minutes retrieving mail that has nothing to do with the report.
struct TimesheetBodyScopeTests {
    private func candidate(hasProject: Bool = false, isAccepted: Bool = false, loggedHours: Double = 0,
                           messages: [(UUID, Bool)]) -> TimesheetBodyScope.Candidate {
        .init(conversationID: UUID(), hasProject: hasProject, isAccepted: isAccepted,
              loggedHours: loggedHours, messages: messages.map { .init(id: $0.0, hasMessageID: $0.1) })
    }

    @Test func relevanceIsProjectOrAcceptedOrLoggedTime() {
        #expect(TimesheetBodyScope.isRelevant(hasProject: true, isAccepted: false, loggedHours: 0))
        #expect(TimesheetBodyScope.isRelevant(hasProject: false, isAccepted: true, loggedHours: 0))
        #expect(TimesheetBodyScope.isRelevant(hasProject: false, isAccepted: false, loggedHours: 0.25))
        #expect(!TimesheetBodyScope.isRelevant(hasProject: false, isAccepted: false, loggedHours: 0))
    }

    @Test func irrelevantConversationsAreSkippedWithAStatedReason() {
        let id = UUID()
        let plan = TimesheetBodyScope.plan([candidate(messages: [(id, true)])])
        #expect(plan.requested.isEmpty)
        #expect(plan.skipped[id] == .skippedNotRelevant)
        #expect(plan.isEmpty)
    }

    // No Mail id means the lookup would certainly fail — don't spend the round trip to discover that.
    @Test func aMessageWithNoMailIDIsSkippedWithoutAFetch() {
        let withID = UUID(), withoutID = UUID()
        let plan = TimesheetBodyScope.plan([
            candidate(hasProject: true, messages: [(withID, true), (withoutID, false)]),
        ])
        #expect(plan.requested == [withID])
        #expect(plan.skipped[withoutID] == .skippedNoMessageID)
    }

    @Test func planPreservesOrderAndDeduplicates() {
        let a = UUID(), b = UUID()
        let plan = TimesheetBodyScope.plan([
            candidate(isAccepted: true, messages: [(a, true), (b, true)]),
            candidate(isAccepted: true, messages: [(a, true)]),      // same message again
        ])
        #expect(plan.requested == [a, b])
    }

    @Test func relevantAndIrrelevantConversationsAreBothAccountedFor() {
        let keep = UUID(), drop = UUID()
        let plan = TimesheetBodyScope.plan([
            candidate(loggedHours: 0.5, messages: [(keep, true)]),
            candidate(messages: [(drop, true)]),
        ])
        #expect(plan.requested == [keep])
        #expect(plan.skipped == [drop: .skippedNotRelevant])     // every message has an outcome
    }

    // Permission and availability apply to every remaining fetch — repeating them N times is noise.
    @Test func permissionAndAvailabilityAreFatal_otherErrorsAreNot() {
        #expect(TimesheetBodyScope.isFatal(.permissionDenied))
        #expect(TimesheetBodyScope.isFatal(.mailUnavailable))
        #expect(!TimesheetBodyScope.isFatal(.scriptError("[-1728] can't get message id 4411")))
    }

    @Test func emptyInput_isAnEmptyPlan() {
        let plan = TimesheetBodyScope.plan([])
        #expect(plan.requested.isEmpty && plan.skipped.isEmpty && plan.isEmpty)
    }
}
