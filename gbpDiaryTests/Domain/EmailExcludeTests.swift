import Testing
import Foundation
@testable import gbpDiary

@Suite("EmailExclude")
struct EmailExcludeTests {
    private func sender(_ p: String) -> EmailExcludeRule { EmailExcludeRule(field: .sender, pattern: p) }
    private func subject(_ p: String) -> EmailExcludeRule { EmailExcludeRule(field: .subject, pattern: p) }

    @Test func isExcluded_senderFullAddress_caseInsensitive() {
        #expect(EmailExcludeMatching.isExcluded(fromAddress: "News@X.com", subject: "hi", rules: [sender("news@x.com")]))
        #expect(!EmailExcludeMatching.isExcluded(fromAddress: "other@x.com", subject: "hi", rules: [sender("news@x.com")]))
    }

    @Test func isExcluded_senderDomainRule_matchesAnyAddressOnDomain() {
        #expect(EmailExcludeMatching.isExcluded(fromAddress: "a@mail.x.com", subject: "", rules: [sender("mail.x.com")]))
        #expect(EmailExcludeMatching.isExcluded(fromAddress: "b@x.com", subject: "", rules: [sender("@x.com")]))
        #expect(!EmailExcludeMatching.isExcluded(fromAddress: "b@y.com", subject: "", rules: [sender("@x.com")]))
    }

    @Test func isExcluded_subjectRule_matchesSubstringCaseInsensitively() {
        let rules = [subject("[lsc-all]")]
        #expect(EmailExcludeMatching.isExcluded(fromAddress: "a@x.com", subject: "[LSC-all] Weekly digest", rules: rules))
        #expect(EmailExcludeMatching.isExcluded(fromAddress: "a@x.com", subject: "Re: [lsc-all] reply", rules: rules))
        #expect(!EmailExcludeMatching.isExcluded(fromAddress: "a@x.com", subject: "unrelated", rules: rules))
    }

    @Test func isExcluded_blankOrEmpty_false() {
        #expect(!EmailExcludeMatching.isExcluded(fromAddress: "", subject: "", rules: [sender("x.com")]))
        #expect(!EmailExcludeMatching.isExcluded(fromAddress: "a@x.com", subject: "hi", rules: []))
    }

    @Test func normalizePattern_sender_lowercases_subject_preservesCase() {
        #expect(EmailExcludeMatching.normalizePattern("  News@X.com ", field: .sender) == "news@x.com")
        #expect(EmailExcludeMatching.normalizePattern("  [LSC-all] ", field: .subject) == "[LSC-all]")
        #expect(EmailExcludeMatching.normalizePattern("   ", field: .subject) == nil)
    }

    @Test func suggestions_forAddress_offersAddressAndDomain() {
        #expect(EmailExcludeMatching.suggestions(forAddress: "News@X.com") == ["news@x.com", "@x.com"])
        #expect(EmailExcludeMatching.suggestions(forAddress: "notanemail").isEmpty)
    }

    @Test func store_addRemove_typedRules() {
        let d = UserDefaults(suiteName: "excl-\(UUID())")!
        EmailExcludeStore.add(field: .sender, pattern: "News@X.com", d)
        EmailExcludeStore.add(field: .sender, pattern: "news@x.com", d)   // dup after normalise → ignored
        EmailExcludeStore.add(field: .subject, pattern: "[lsc-all]", d)
        let rules = EmailExcludeStore.load(d)
        #expect(rules.count == 2)
        #expect(rules.contains(EmailExcludeRule(field: .sender, pattern: "news@x.com")))
        #expect(rules.contains(EmailExcludeRule(field: .subject, pattern: "[lsc-all]")))
        EmailExcludeStore.remove(EmailExcludeRule(field: .sender, pattern: "news@x.com"), d)
        #expect(EmailExcludeStore.load(d) == [EmailExcludeRule(field: .subject, pattern: "[lsc-all]")])
    }

    @Test func store_migratesLegacySenderList() {
        let d = UserDefaults(suiteName: "excl-\(UUID())")!
        d.set(["news@x.com", "@spam.com"], forKey: "email.excludeSenders")
        let rules = EmailExcludeStore.load(d)
        #expect(rules == [EmailExcludeRule(field: .sender, pattern: "news@x.com"),
                          EmailExcludeRule(field: .sender, pattern: "@spam.com")])
    }
}
