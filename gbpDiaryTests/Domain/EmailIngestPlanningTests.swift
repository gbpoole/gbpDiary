import Testing
import Foundation
@testable import gbpDiary

@Suite("EmailIngestPlanning")
struct EmailIngestPlanningTests {
    private func draft(_ id: String, _ addr: String, _ subject: String,
                       _ direction: EmailDirection = .inbox) -> MailMessageDraft {
        MailMessageDraft(messageId: id, address: addr, name: nil, subject: subject,
                         date: Date(timeIntervalSince1970: 1000), direction: direction)
    }

    private func key(_ d: MailMessageDraft, account: String = "acct") -> String {
        MailScriptParsing.dedupeKey(messageId: d.messageId, account: account,
                                    mailbox: EmailIngestPlanning.mailbox(for: d.direction),
                                    date: d.date, fromAddress: d.address, subject: d.subject)
    }

    @Test func candidates_classifiesNewIngestedAndSkipped() {
        let a = draft("<a>", "a@x.com", "Hello")
        let b = draft("<b>", "b@x.com", "World")
        let c = draft("<c>", "c@x.com", "New one")
        let existing: [String: Bool] = [key(a): false, key(b): true]   // a ingested, b skipped

        let result = EmailIngestPlanning.candidates(drafts: [a, b, c], account: "acct", existing: existing)
        #expect(result.map(\.state) == [.ingested, .notChosen, .new])
    }

    @Test func defaultSelected_onForNewAndIngested_offForSkipped() {
        let new = EmailIngestCandidate(key: "k1", draft: draft("<1>", "a@x", "s"), state: .new)
        let ingested = EmailIngestCandidate(key: "k2", draft: draft("<2>", "b@x", "s"), state: .ingested)
        let skipped = EmailIngestCandidate(key: "k3", draft: draft("<3>", "c@x", "s"), state: .notChosen)
        #expect(new.defaultSelected == true)
        #expect(ingested.defaultSelected == true)
        #expect(skipped.defaultSelected == false)
    }

    @Test func mailbox_mapsDirection() {
        #expect(EmailIngestPlanning.mailbox(for: .inbox) == "INBOX")
        #expect(EmailIngestPlanning.mailbox(for: .sent) == "Sent")
    }
}
