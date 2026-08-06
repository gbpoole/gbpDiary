import Testing
import Foundation
@testable import gbpDiary

@Suite("EmailExclude")
struct EmailExcludeTests {
    @Test func isExcluded_fullAddress_caseInsensitive() {
        #expect(EmailExcludeMatching.isExcluded(address: "News@X.com", rules: ["news@x.com"]))
        #expect(!EmailExcludeMatching.isExcluded(address: "other@x.com", rules: ["news@x.com"]))
    }

    @Test func isExcluded_domainRule_matchesAnyAddressOnDomain() {
        #expect(EmailExcludeMatching.isExcluded(address: "a@mail.x.com", rules: ["mail.x.com"]))
        #expect(EmailExcludeMatching.isExcluded(address: "b@x.com", rules: ["@x.com"]))
        #expect(!EmailExcludeMatching.isExcluded(address: "b@y.com", rules: ["@x.com"]))
    }

    @Test func isExcluded_domainRule_doesNotMatchSubdomainMismatch() {
        // "@x.com" matches x.com exactly, not mail.x.com
        #expect(!EmailExcludeMatching.isExcluded(address: "a@mail.x.com", rules: ["@x.com"]))
    }

    @Test func isExcluded_blankAddressOrRules_false() {
        #expect(!EmailExcludeMatching.isExcluded(address: "", rules: ["x.com"]))
        #expect(!EmailExcludeMatching.isExcluded(address: "a@x.com", rules: ["", "  "]))
    }

    @Test func suggestions_forAddress_offersAddressAndDomain() {
        #expect(EmailExcludeMatching.suggestions(forAddress: "News@X.com") == ["news@x.com", "@x.com"])
        #expect(EmailExcludeMatching.suggestions(forAddress: "notanemail").isEmpty)
    }

    @Test func store_addDedupsAndRemove() {
        let d = UserDefaults(suiteName: "excl-\(UUID())")!
        EmailExcludeStore.add("News@X.com", d)
        EmailExcludeStore.add("news@x.com", d)   // dup (normalised)
        #expect(EmailExcludeStore.load(d) == ["news@x.com"])
        EmailExcludeStore.remove("news@x.com", d)
        #expect(EmailExcludeStore.load(d).isEmpty)
    }
}
