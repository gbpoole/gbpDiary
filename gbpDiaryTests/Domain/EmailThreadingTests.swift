import Testing
import Foundation
@testable import gbpDiary

@Suite("EmailThreading")
struct EmailThreadingTests {
    @Test func normalizedSubject_stripsReplyAndForwardPrefixes() {
        #expect(EmailThreading.normalizedSubject("Re: Hello") == "hello")
        #expect(EmailThreading.normalizedSubject("FWD: Fw: Re: Budget") == "budget")
        #expect(EmailThreading.normalizedSubject("  Plain  ") == "plain")
    }

    @Test func threadKey_sameSubjectAndParty_matchAcrossReplies() {
        let a = EmailThreading.threadKey(subject: "Re: Sync", party: "person-1")
        let b = EmailThreading.threadKey(subject: "Sync", party: "Person-1")
        #expect(a == b)
    }

    @Test func threadKey_differentParty_differs() {
        let a = EmailThreading.threadKey(subject: "Sync", party: "a@x.com")
        let b = EmailThreading.threadKey(subject: "Sync", party: "b@x.com")
        #expect(a != b)
    }
}
