import Testing
import Foundation
@testable import gbpDiary

@Suite("EmailSummary")
struct EmailSummaryTests {
    private func ctx(me: SummaryPerson? = nil, other: SummaryPerson? = nil,
                     sent: Bool = false, roster: [SummaryPerson] = []) -> SummaryContext {
        SummaryContext(me: me, other: other, directionIsSent: sent, roster: roster)
    }

    @Test func prompt_includesSubjectAndBody() {
        let p = EmailSummaryPrompt.build(context: ctx(), subject: "Q3 budget", body: "Please review.")
        #expect(p.contains("Subject: Q3 budget"))
        #expect(p.contains("Please review."))
    }

    @Test func prompt_blankSubject_usesPlaceholder() {
        let p = EmailSummaryPrompt.build(context: ctx(), subject: "", body: "hi")
        #expect(p.contains("Subject: (no subject)"))
    }

    @Test func prompt_includesIdentityDirectionAndRoster() {
        let me = SummaryPerson(name: "Greg Poole", emails: ["greg@x.com"])
        let other = SummaryPerson(name: "Ada Lovelace", emails: ["ada@y.com"])
        let roster = [SummaryPerson(name: "Bob Jones", emails: ["bob@z.com"])]
        // Received
        let recv = EmailSummaryPrompt.build(context: ctx(me: me, other: other, sent: false, roster: roster),
                                            subject: "Sync", body: "hi")
        #expect(recv.contains("You are Greg Poole"))
        #expect(recv.contains("greg@x.com"))
        #expect(recv.contains("You received this email from Ada Lovelace <ada@y.com>."))
        #expect(recv.contains("Known people: Bob Jones <bob@z.com>"))
        // Sent
        let sent = EmailSummaryPrompt.build(context: ctx(me: me, other: other, sent: true), subject: "Sync", body: "hi")
        #expect(sent.contains("You sent this email to Ada Lovelace <ada@y.com>."))
    }

    @Test func prompt_omitsMissingPieces() {
        let p = EmailSummaryPrompt.build(context: ctx(), subject: "S", body: "b")
        #expect(!p.contains("You are "))
        #expect(!p.contains("Known people:"))
        #expect(p.contains("You received this email."))   // direction still stated
    }

    @Test func instructions_containKeyRules() {
        let i = EmailSummaryPrompt.instructions
        #expect(i.contains("\"you\""))
        #expect(i.lowercased().contains("title"))
        #expect(i.lowercased().contains("signature"))
    }

    @Test func roster_capsAndOrdersPriorityFirst() {
        let a = EmailSummaryRoster.Candidate(id: UUID(), name: "Zoe", emails: ["z@x"], isPriority: true)
        let b = EmailSummaryRoster.Candidate(id: UUID(), name: "Ann", emails: ["a@x"], isPriority: false)
        let c = EmailSummaryRoster.Candidate(id: UUID(), name: "Cy", emails: ["c@x"], isPriority: false)
        let out = EmailSummaryRoster.build([b, a, c], limit: 2)
        #expect(out.count == 2)
        #expect(out[0].name == "Zoe")     // priority first
        #expect(out[1].name == "Ann")     // then alphabetical (Ann before Cy)
    }

    @Test func roster_dedupsById() {
        let id = UUID()
        let a = EmailSummaryRoster.Candidate(id: id, name: "Ann", emails: ["a@x"], isPriority: false)
        let dup = EmailSummaryRoster.Candidate(id: id, name: "Ann", emails: ["a@x"], isPriority: false)
        #expect(EmailSummaryRoster.build([a, dup]).count == 1)
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

    @Test func needsSummary_pendingDismissedAndStaleVersion() {
        // pending + not dismissed → yes; dismissed → no.
        #expect(EmailSummaryPlanning.needsSummary(state: .pending, dismissed: false, version: 1, current: 1) == true)
        #expect(EmailSummaryPlanning.needsSummary(state: .pending, dismissed: true, version: 1, current: 1) == false)
        // done at current version → no; done at stale version → yes (re-summarise after tuning).
        #expect(EmailSummaryPlanning.needsSummary(state: .done, dismissed: false, version: 2, current: 2) == false)
        #expect(EmailSummaryPlanning.needsSummary(state: .done, dismissed: false, version: 1, current: 2) == true)
        // failed → never auto-retried.
        #expect(EmailSummaryPlanning.needsSummary(state: .failed, dismissed: false, version: 0, current: 2) == false)
    }
}
