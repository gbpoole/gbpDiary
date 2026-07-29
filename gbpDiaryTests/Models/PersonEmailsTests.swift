import Testing
import Foundation
@testable import gbpDiary

@Suite("Person emails")
@MainActor
struct PersonEmailsTests {

    @Test func emails_roundTripThroughJSON() {
        let p = Person(name: "A")
        #expect(p.emails == [])
        p.emails = ["one@x.com", "two@x.com"]
        #expect(p.emails == ["one@x.com", "two@x.com"])
    }

    @Test func primaryEmail_isFirstOrNil() {
        let p = Person(name: "A")
        #expect(p.primaryEmail == nil)
        p.emails = ["primary@x.com", "alt@x.com"]
        #expect(p.primaryEmail == "primary@x.com")
    }

    @Test func appendingEmail_dedupsCaseInsensitively_preservesOrder() {
        let start = ["primary@x.com", "alt@x.com"]
        #expect(Person.appendingEmail("new@x.com", to: start) == ["primary@x.com", "alt@x.com", "new@x.com"])
        // Case-insensitive duplicate → no change, order/primary preserved.
        #expect(Person.appendingEmail("PRIMARY@x.com", to: start) == start)
    }

    @Test func appendingEmail_ignoresBlank() {
        let start = ["primary@x.com"]
        #expect(Person.appendingEmail("   ", to: start) == start)
        #expect(Person.appendingEmail("", to: start) == start)
    }

    @Test func migratedEmails_promotesLegacyEmail_whenListEmpty() {
        #expect(Person.migratedEmails(legacyEmail: "old@x.com", existingEmails: []) == ["old@x.com"])
        #expect(Person.migratedEmails(legacyEmail: "  trimmed@x.com  ", existingEmails: []) == ["trimmed@x.com"])
    }

    @Test func migratedEmails_returnsNil_whenAlreadyHasEmails() {
        #expect(Person.migratedEmails(legacyEmail: "old@x.com", existingEmails: ["already@x.com"]) == nil)
    }

    @Test func migratedEmails_returnsNil_whenLegacyBlank() {
        #expect(Person.migratedEmails(legacyEmail: nil, existingEmails: []) == nil)
        #expect(Person.migratedEmails(legacyEmail: "   ", existingEmails: []) == nil)
    }
}
