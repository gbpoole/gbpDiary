import Foundation
import Testing
@testable import gbpDiary

struct EmailSelfMatchingTests {
    @Test func normalizedAddresses_trimsLowercasesDedupsAndDropsBlanks() {
        let set = EmailSelfMatching.normalizedAddresses(["  Me@X.com ", "me@x.com", "", "   ", "Other@Y.com"])
        #expect(set == ["me@x.com", "other@y.com"])
    }

    @Test func isInboxFromSelf_trueForInboxSenderMatch_caseAndSpaceInsensitive() {
        let mine: Set<String> = ["me@x.com"]
        #expect(EmailSelfMatching.isInboxFromSelf(direction: .inbox, fromAddress: "me@x.com", myAddresses: mine))
        #expect(EmailSelfMatching.isInboxFromSelf(direction: .inbox, fromAddress: "  ME@X.com ", myAddresses: mine))
    }

    @Test func isInboxFromSelf_falseForSentEvenWhenSenderIsMine() {
        // A sent email is the real outgoing copy, never a loopback.
        #expect(!EmailSelfMatching.isInboxFromSelf(direction: .sent, fromAddress: "me@x.com",
                                                   myAddresses: ["me@x.com"]))
    }

    @Test func isInboxFromSelf_falseWhenSenderNotMine() {
        #expect(!EmailSelfMatching.isInboxFromSelf(direction: .inbox, fromAddress: "other@y.com",
                                                   myAddresses: ["me@x.com"]))
    }

    @Test func isInboxFromSelf_falseForBlankAddressOrEmptySet() {
        #expect(!EmailSelfMatching.isInboxFromSelf(direction: .inbox, fromAddress: "  ",
                                                   myAddresses: ["me@x.com"]))
        #expect(!EmailSelfMatching.isInboxFromSelf(direction: .inbox, fromAddress: "me@x.com",
                                                   myAddresses: []))
    }
}
