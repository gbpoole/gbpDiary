import Testing
import Foundation
@testable import gbpDiary

@Suite("EmailSummary")
struct EmailSummaryTests {
    @Test func prompt_includesSubjectAndSender() {
        let p = EmailSummaryPrompt.build(subject: "Q3 budget", from: "Ada Lovelace", body: "Please review.")
        #expect(p.contains("Subject: Q3 budget"))
        #expect(p.contains("From: Ada Lovelace"))
        #expect(p.contains("Please review."))
    }

    @Test func prompt_blankSubject_usesPlaceholder() {
        let p = EmailSummaryPrompt.build(subject: "", from: "x", body: "hi")
        #expect(p.contains("Subject: (no subject)"))
    }

    @Test func clampBody_capsLengthAndTrims() {
        let body = "  " + String(repeating: "a", count: 10) + "  "
        #expect(EmailSummaryPrompt.clampBody(body, limit: 4) == "aaaa")
        #expect(EmailSummaryPrompt.clampBody("  short  ", limit: 100) == "short")
    }

    @Test func clean_trimsCollapsesAndCaps() {
        #expect(EmailSummaryText.clean("  a\n\n  b   c \t") == "a b c")
        let long = String(repeating: "x", count: EmailSummaryText.maxChars + 50)
        let cleaned = EmailSummaryText.clean(long)
        #expect(cleaned.hasSuffix("…"))
        #expect(cleaned.count <= EmailSummaryText.maxChars + 1)   // + the ellipsis
    }

    @Test func state_rawRoundTrips() {
        for s in [EmailSummaryState.pending, .done, .failed, .unavailable] {
            #expect(EmailSummaryState(rawValue: s.rawValue) == s)
        }
    }

    @Test func needsSummary_onlyPendingAndNotDismissed() {
        #expect(EmailSummaryPlanning.needsSummary(state: .pending, dismissed: false) == true)
        #expect(EmailSummaryPlanning.needsSummary(state: .pending, dismissed: true) == false)
        #expect(EmailSummaryPlanning.needsSummary(state: .done, dismissed: false) == false)
        #expect(EmailSummaryPlanning.needsSummary(state: .failed, dismissed: false) == false)
    }
}
