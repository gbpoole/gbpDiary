import Foundation
import Testing
@testable import gbpDiary

struct PersonSearchTests {
    private func match(_ query: String, name: String = "", emails: [String] = [],
                       institution: String? = nil, tags: [String] = []) -> Bool {
        PersonSearch.matches(query: query, name: name, emails: emails, institution: institution, tags: tags)
    }

    @Test func emptyQuery_matchesEverything() {
        #expect(match("", name: "Anyone"))
        #expect(match("   ", name: "Anyone"))
    }

    @Test func matchesName_caseInsensitive() {
        #expect(match("sam", name: "Sam Lee"))
        #expect(match("SAM", name: "Samantha Cho"))
    }

    // Every email is searchable, not just the primary (first) one.
    @Test func matchesAnyEmail_notJustPrimary() {
        #expect(match("work", name: "Sam Lee", emails: ["sam@home.com", "sam@work.org"]))
    }

    @Test func matchesInstitutionAndTag() {
        #expect(match("swin", name: "Sam", institution: "Swinburne"))
        #expect(match("radio", name: "Sam", tags: ["radio", "optical"]))
    }

    // "sx" completes only by spanning name→email ("Sam" gives s, "xavier" gives x); no single field
    // contains the subsequence, so per-field matching must NOT match (a whole-haystack match would).
    @Test func doesNotSpanAcrossFields() {
        #expect(!match("sx", name: "Sam Lee", emails: ["xavier@work.org"]))
    }

    @Test func noMatch_returnsFalse() {
        #expect(!match("zzz", name: "Sam Lee", emails: ["sam@work.org"], institution: "Swinburne", tags: ["radio"]))
    }
}
