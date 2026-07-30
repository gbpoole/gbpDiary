import Testing
import Foundation
@testable import gbpDiary

@Suite("EmailPersonMatching")
struct EmailPersonMatchingTests {
    private let alice = UUID()
    private let bob = UUID()

    private var people: [PersonRef] {
        [
            PersonRef(id: alice, name: "Alice", emails: ["alice@x.com", "a.smith@work.org"]),
            PersonRef(id: bob, name: "Bob", emails: ["bob@y.com"]),
        ]
    }

    @Test func personID_matchesPrimaryAddress() {
        #expect(EmailPersonMatching.personID(forAddress: "alice@x.com", in: people) == alice)
    }

    @Test func personID_matchesSecondaryAddress() {
        #expect(EmailPersonMatching.personID(forAddress: "a.smith@work.org", in: people) == alice)
    }

    @Test func personID_isCaseInsensitive() {
        #expect(EmailPersonMatching.personID(forAddress: "BOB@Y.COM", in: people) == bob)
    }

    @Test func personID_nilWhenNoMatch() {
        #expect(EmailPersonMatching.personID(forAddress: "carol@z.com", in: people) == nil)
    }

    @Test func personID_nilForBlankAddress() {
        #expect(EmailPersonMatching.personID(forAddress: "   ", in: people) == nil)
        #expect(EmailPersonMatching.personID(forAddress: "", in: people) == nil)
    }

    @Test func personID_trimsWhitespaceBeforeMatching() {
        #expect(EmailPersonMatching.personID(forAddress: "  alice@x.com  ", in: people) == alice)
    }
}
