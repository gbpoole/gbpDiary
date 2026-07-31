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

    // Cleaned out of the day's list (persists across refreshes; undoable).
    var dismissed: Bool = false
    // The resolved "other party" (Inbox = sender, Sent = recipient); nil until matched/reconciled.
    var person: Person?
    // Projects this email is filed under.
    @Relationship(inverse: \Project.emails) var projects: [Project] = []
    // Time entries logged against sending this email (count toward the day's activity total).
    @Relationship(deleteRule: .nullify, inverse: \TaskTimeEntry.email) var timeEntries: [TaskTimeEntry] = []

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
