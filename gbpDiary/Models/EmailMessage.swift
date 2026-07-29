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
