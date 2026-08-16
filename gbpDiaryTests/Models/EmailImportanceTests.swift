import Foundation
import Testing
@testable import gbpDiary

@MainActor
struct EmailImportanceTests {
    private func email() -> EmailMessage {
        EmailMessage(messageId: "m", account: "a", mailbox: "INBOX", direction: .inbox,
                     fromAddress: "x@y.com", fromName: nil, subject: "s", date: FixedDates.reference)
    }

    @Test func enum_shortWeightRankAndOrdering() {
        #expect(EmailImportance.low.short == "")
        #expect(EmailImportance.medium.short == "M")
        #expect(EmailImportance.high.short == "H")
        #expect(EmailImportance.low.weight == 0.0)
        #expect(EmailImportance.medium.weight == 0.5)
        #expect(EmailImportance.high.weight == 1.0)
        #expect(EmailImportance.low.rank < EmailImportance.medium.rank)
        #expect(EmailImportance.medium.rank < EmailImportance.high.rank)
    }

    @Test func message_defaultsToLow_andIsNotImportant() {
        let e = email()
        #expect(e.importance == .low)
        #expect(!e.isImportant)
    }

    @Test func message_importance_roundTripsThroughRaw() {
        let e = email()
        e.importance = .high
        #expect(e.importanceRaw == EmailImportance.high.rawValue)
        #expect(e.importance == .high)
        #expect(e.isImportant)
        e.importance = .medium
        #expect(e.isImportant)
        e.importance = .low
        #expect(!e.isImportant)
    }

    @Test func message_unknownRaw_fallsBackToLow() {
        let e = email()
        e.importanceRaw = "bogus"
        #expect(e.importance == .low)
    }
}
