import Foundation
import SwiftData

// A cached envelope-metadata record for one email fetched from IMAP. Bodies are never stored.
// Shown in the diary day's Email section, filtered by `date` (the message's own date). All stored
// properties have defaults so SwiftData can lightweight-migrate the existing store.
@Model final class EmailMessage {
    @Attribute(.unique) var id: UUID = UUID()
    var messageId: String = ""      // RFC Message-ID; "" when the server omits it
    var account: String = ""        // owning account (username) — supports future multi-account
    var mailbox: String = ""        // "INBOX" or the configured Sent-mailbox name
    var direction: EmailDirection = EmailDirection.inbox
    var fromAddress: String = ""
    var fromName: String?
    var subject: String = ""
    var date: Date = Date.distantPast
    var fetchedAt: Date = Date()

    // Triage: `dismissed` hides the email; `accepted` promotes it to the diary. Neither → unclassified
    // (needs triage). See EmailTriageState. `accepted` defaults false; a one-time migration marks
    // pre-existing non-dismissed emails accepted so they stay on the diary.
    var dismissed: Bool = false
    var accepted: Bool = false

    var triageState: EmailTriageState { .from(dismissed: dismissed, accepted: accepted) }
    func accept() { accepted = true; dismissed = false }
    func triageDismiss() { dismissed = true }
    func unclassify() { accepted = false; dismissed = false }
    // The resolved "other party" (Inbox = sender, Sent = recipient); nil until matched/reconciled.
    var person: Person?
    // Projects this email is filed under.
    @Relationship(inverse: \Project.emails) var projects: [Project] = []
    // Time entries logged against sending this email (count toward the day's activity total).
    @Relationship(deleteRule: .nullify, inverse: \TaskTimeEntry.email) var timeEntries: [TaskTimeEntry] = []
    // Todos made from this email (nullify — deleting the email leaves the tasks, just unlinked).
    @Relationship(deleteRule: .nullify, inverse: \Task.originEmail) var tasks: [Task] = []

    var hasTasks: Bool { !tasks.isEmpty }
    var hasOpenTask: Bool { tasks.contains(where: \.isOpen) }

    // On-device AI summary (the body is fetched transiently and never stored — only this summary is).
    var summary: String?
    // Raw of EmailSummaryState: "pending" (needs one) | "done" | "failed" | "unavailable".
    var summaryState: String = EmailSummaryState.pending.rawValue
    // Prompt version used for the stored summary; a bump re-summarises (see EmailSummaryPlanning).
    var summaryPromptVersion: Int = 0
    // On-device model's picked project for triage suggestions (never auto-applied); nil if none/unknown.
    var suggestedProjectID: UUID?

    init(messageId: String, account: String, mailbox: String, direction: EmailDirection,
         fromAddress: String, fromName: String?, subject: String, date: Date, id: UUID = UUID()) {
        self.id = id
        self.messageId = messageId
        self.account = account
        self.mailbox = mailbox
        self.direction = direction
        self.fromAddress = fromAddress
        self.fromName = fromName
        self.subject = subject
        self.date = date
        self.fetchedAt = Date()
    }
}
