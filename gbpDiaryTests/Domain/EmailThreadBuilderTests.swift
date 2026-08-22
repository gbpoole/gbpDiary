import Foundation
import Testing
@testable import gbpDiary

@MainActor
struct EmailThreadBuilderTests {
    private let cal = Calendar(identifier: .gregorian)
    private func at(_ day: Int, _ hour: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 1, day: day, hour: hour))!
    }
    private func msg(_ subject: String, _ dir: EmailDirection, _ addr: String, _ hour: Int,
                     person: Person? = nil) -> EmailMessage {
        let e = EmailMessage(messageId: "\(subject)-\(hour)", account: "a", mailbox: "m", direction: dir,
                             fromAddress: addr, fromName: nil, subject: subject, date: at(5, hour))
        e.person = person
        return e
    }

    @Test func conversationUnitesSentAndReceived() {
        // A received message from X and your sent reply to X (Sent stores the recipient as fromAddress)
        // share the same normalized subject + party → one thread.
        let recv = msg("ADACS proposal", .inbox, "x@y.com", 9)
        let sent = msg("Re: ADACS proposal", .sent, "x@y.com", 10)
        let threads = EmailThreadBuilder.threads(from: [recv, sent])
        #expect(threads.count == 1)
        #expect(threads[0].count == 2)
        #expect(threads[0].sentCount == 1)
        #expect(threads[0].receivedCount == 1)
        #expect(threads[0].latest.date == sent.date)   // sorted latest-first
    }

    @Test func sameSubjectMerges_differentSubjectSplits() {
        let a = msg("ADACS proposal", .inbox, "x@y.com", 9)
        let b = msg("Re: ADACS proposal", .inbox, "z@y.com", 10)   // different party, same subject → merges
        let c = msg("Gen3 timing", .inbox, "x@y.com", 11)          // different subject → separate
        let threads = EmailThreadBuilder.threads(from: [a, b, c])
        #expect(threads.count == 2)
        #expect(threads.first { $0.subject.lowercased().contains("adacs") }?.count == 2)
    }

    @Test func multiPartyExchangeStaysOneThread() {
        // The reported bug: an exchange involving two people (Jarrod + Cheryl) split across threads.
        let m1 = msg("Project plan", .inbox, "jarrod@x.com", 9)
        let m2 = msg("Re: Project plan", .sent, "cheryl@x.com", 10)
        let m3 = msg("Re: Project plan", .inbox, "cheryl@x.com", 11)
        let threads = EmailThreadBuilder.threads(from: [m1, m2, m3])
        #expect(threads.count == 1)
        #expect(threads[0].count == 3)
    }

    @Test func partyMatchesByResolvedPersonAcrossAddresses() {
        // When both messages resolve to the same Person, differing addresses still unite the thread.
        let p = Person(name: "Suzanne")
        let a = msg("Budget", .inbox, "suzanne@work.com", 9, person: p)
        let b = msg("Re: Budget", .sent, "suzanne@home.com", 10, person: p)
        let threads = EmailThreadBuilder.threads(from: [a, b])
        #expect(threads.count == 1)
        #expect(threads[0].count == 2)
    }
}
