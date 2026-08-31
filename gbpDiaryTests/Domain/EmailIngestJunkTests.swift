import Foundation
import SwiftData
import Testing
@testable import gbpDiary

@MainActor
struct EmailIngestJunkTests {
    private func context() throws -> ModelContext { ModelContext(try TestModelContainer.make()) }

    private func draft(_ msgId: String, _ from: String, _ subject: String, junk: Bool,
                       date: Date = FixedDates.reference) -> MailMessageDraft {
        MailMessageDraft(messageId: msgId, address: from, name: nil, subject: subject, date: date,
                         direction: .inbox, isJunk: junk)
    }
    private func stored(_ ctx: ModelContext, _ msgId: String, _ from: String, _ subject: String,
                        date: Date = FixedDates.reference) -> EmailMessage {
        let e = EmailMessage(messageId: msgId, account: "a", mailbox: "INBOX", direction: .inbox,
                             fromAddress: from, fromName: nil, subject: subject, date: date)
        e.accept()   // it slipped into the diary before Mail flagged it
        ctx.insert(e)
        return e
    }

    @Test func junkDraftDismissesTheStoredCopy() throws {
        let ctx = try context()
        let existing = stored(ctx, "42", "spam@x.com", "Buy now")
        #expect(existing.triageState == .accepted)
        let added = EmailIngest.upsert([draft("42", "spam@x.com", "Buy now", junk: true)],
                                       account: "a", existing: [existing], people: [], context: ctx)
        #expect(added == 0)                             // nothing new added
        #expect(existing.triageState == .dismissed)     // stored copy dismissed (self-heal)
    }

    @Test func newJunkIsNotIngested() throws {
        let ctx = try context()
        let added = EmailIngest.upsert([draft("99", "spam@x.com", "Buy now", junk: true)],
                                       account: "a", existing: [], people: [], context: ctx)
        #expect(added == 0)
        let all = (try? ctx.fetch(FetchDescriptor<EmailMessage>())) ?? []
        #expect(all.isEmpty)                            // new junk never stored
    }

    @Test func nonJunkStillIngests() throws {
        let ctx = try context()
        let added = EmailIngest.upsert([draft("7", "a@x.com", "Hello", junk: false)],
                                       account: "a", existing: [], people: [], context: ctx)
        #expect(added == 1)
    }
}
