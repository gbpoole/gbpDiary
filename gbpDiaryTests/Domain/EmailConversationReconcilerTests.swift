import Foundation
import SwiftData
import Testing
@testable import gbpDiary

@MainActor
struct EmailConversationReconcilerTests {
    private func context() throws -> ModelContext {
        ModelContext(try TestModelContainer.make())
    }
    private func email(_ ctx: ModelContext, subject: String, msgId: String = "", inReplyTo: String? = nil,
                       refs: [String] = [], date: Date = FixedDates.reference,
                       direction: EmailDirection = .inbox) -> EmailMessage {
        let e = EmailMessage(messageId: msgId.isEmpty ? UUID().uuidString : msgId, account: "a",
                             mailbox: "INBOX", direction: direction, fromAddress: "x@y.com", fromName: nil,
                             subject: subject, date: date)
        e.rfcMessageId = msgId
        e.inReplyTo = inReplyTo
        e.references = refs
        ctx.insert(e)
        return e
    }

    @Test func replyGraphGroupsIntoOneConversation_otherSubjectSeparate() throws {
        let ctx = try context()
        let a = email(ctx, subject: "Plan", msgId: "M1")
        let b = email(ctx, subject: "Re: Plan", msgId: "M2", inReplyTo: "M1", refs: ["M1"])
        let c = email(ctx, subject: "Unrelated", msgId: "M3")
        EmailConversationReconciler.reconcile(emails: [a, b, c], context: ctx)
        #expect(a.conversation != nil)
        #expect(a.conversation?.id == b.conversation?.id)   // reply chain → one conversation
        #expect(c.conversation?.id != a.conversation?.id)   // different subject/graph → separate
        let convos = (try? ctx.fetch(FetchDescriptor<EmailConversation>())) ?? []
        #expect(convos.count == 2)
    }

    @Test func foldsLegacyStateOntoConversation() throws {
        let ctx = try context()
        let p = Project(name: "NODES"); ctx.insert(p)
        let per = Person(name: "Suzanne"); ctx.insert(per)
        let a = email(ctx, subject: "Budget", msgId: "M1")
        let b = email(ctx, subject: "Re: Budget", msgId: "M2", refs: ["M1"])
        // Legacy per-message state that migration should fold onto the conversation.
        a.accepted = true; a.projects = [p]; a.importance = .high; a.person = per
        b.accepted = true
        let entry = TaskTimeEntry(date: FixedDates.reference, duration: Duration(value: 0.25, unit: .h))
        entry.email = a; ctx.insert(entry)

        EmailConversationReconciler.reconcile(emails: [a, b], context: ctx)
        let convo = a.conversation
        #expect(convo != nil)
        #expect(convo?.accepted == true)                 // any accepted, none unclassified
        #expect(convo?.importance == .high)              // max across members
        #expect(convo?.person?.id == per.id)
        #expect(convo?.projects.contains { $0.id == p.id } == true)
        #expect(convo?.timeEntries.contains { $0.id == entry.id } == true)   // time reassigned to the thread
    }

    @Test func anyUnclassifiedMemberKeepsConversationToTriage() throws {
        let ctx = try context()
        let a = email(ctx, subject: "X", msgId: "M1"); a.accepted = true
        let b = email(ctx, subject: "Re: X", msgId: "M2", refs: ["M1"])   // unclassified (default)
        EmailConversationReconciler.reconcile(emails: [a, b], context: ctx)
        #expect(a.conversation?.triageState == .unclassified)
    }

    @Test func newReplyJoinsExistingConversationWithoutOverwritingState() throws {
        let ctx = try context()
        let p = Project(name: "NODES"); ctx.insert(p)
        let a = email(ctx, subject: "Grant", msgId: "M1")
        EmailConversationReconciler.reconcile(emails: [a], context: ctx)
        // User triages the conversation.
        let convo = a.conversation!
        convo.accept(); convo.projects = [p]
        // A later reply arrives and is reconciled in.
        let b = email(ctx, subject: "Re: Grant", msgId: "M2", refs: ["M1"])
        EmailConversationReconciler.reconcile(emails: [a, b], context: ctx)
        #expect(b.conversation?.id == convo.id)          // joined the same conversation
        #expect(convo.accepted == true)                  // user state preserved (no reopen)
        #expect(convo.projects.contains { $0.id == p.id } == true)
    }

    @Test func bridgingReplyMergesTwoConversations() throws {
        let ctx = try context()
        // Two separate conversations exist first (no shared refs yet).
        let a = email(ctx, subject: "Topic", msgId: "M1")
        let b = email(ctx, subject: "Topic redux", msgId: "M2")
        EmailConversationReconciler.reconcile(emails: [a, b], context: ctx)
        #expect(a.conversation?.id != b.conversation?.id)
        // A reply that references BOTH bridges them into one conversation.
        let c = email(ctx, subject: "Re: Topic", msgId: "M3", refs: ["M1", "M2"])
        EmailConversationReconciler.reconcile(emails: [a, b, c], context: ctx)
        #expect(a.conversation?.id == b.conversation?.id)
        #expect(a.conversation?.id == c.conversation?.id)
        let convos = (try? ctx.fetch(FetchDescriptor<EmailConversation>())) ?? []
        #expect(convos.count == 1)
    }
}
