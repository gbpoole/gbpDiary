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

    @Test func strippedSubject_stripsPrefixesButPreservesCase() {
        #expect(EmailThreading.strippedSubject("Re: Hello World") == "Hello World")
        #expect(EmailThreading.strippedSubject("FWD: Fw: Re: NODES Budget") == "NODES Budget")
        #expect(EmailThreading.strippedSubject("  Plain Subject  ") == "Plain Subject")
    }

    @Test func threadKey_sameSubjectAcrossReplies_matches() {
        let a = EmailThreading.threadKey(subject: "Re: Sync", party: "person-1")
        let b = EmailThreading.threadKey(subject: "Sync", party: "person-2")
        #expect(a == b)
    }

    @Test func threadKey_sameSubjectDifferentParty_matches() {
        // A multi-party exchange on one subject is a single thread even though the other party varies.
        let a = EmailThreading.threadKey(subject: "Sync", party: "a@x.com")
        let b = EmailThreading.threadKey(subject: "Re: Sync", party: "b@x.com")
        #expect(a == b)
    }

    @Test func threadKey_differentSubject_differs() {
        let a = EmailThreading.threadKey(subject: "Sync", party: "a@x.com")
        let b = EmailThreading.threadKey(subject: "Budget", party: "a@x.com")
        #expect(a != b)
    }

    @Test func threadKey_emptySubject_fallsBackToParty() {
        let a = EmailThreading.threadKey(subject: "", party: "a@x.com")
        let b = EmailThreading.threadKey(subject: "  ", party: "b@x.com")
        let c = EmailThreading.threadKey(subject: "", party: "A@X.com")
        #expect(a != b)   // blank subjects don't merge across parties
        #expect(a == c)   // same party, case-insensitive
    }
}
