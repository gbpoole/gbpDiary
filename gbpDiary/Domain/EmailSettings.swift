import Foundation

// User-configurable Mail source for the diary Email section: which Mail account and which Inbox/Sent
// mailbox names to read. Persisted in UserDefaults (no secrets — Mail holds the credentials).
struct EmailSettings: Equatable {
    var accountName: String
    var inboxMailbox: String
    var sentMailbox: String

    static let `default` = EmailSettings(accountName: "Exchange", inboxMailbox: "Inbox", sentMailbox: "Sent Items")

    var isConfigured: Bool {
        !accountName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !inboxMailbox.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

enum EmailSettingsStore {
    private static let accountKey = "email.mail.account"
    private static let inboxKey = "email.mail.inbox"
    private static let sentKey = "email.mail.sent"

    static func load(_ d: UserDefaults = .standard) -> EmailSettings {
        EmailSettings(
            accountName: d.string(forKey: accountKey) ?? EmailSettings.default.accountName,
            inboxMailbox: d.string(forKey: inboxKey) ?? EmailSettings.default.inboxMailbox,
            sentMailbox: d.string(forKey: sentKey) ?? EmailSettings.default.sentMailbox
        )
    }

    static func save(_ s: EmailSettings, _ d: UserDefaults = .standard) {
        d.set(s.accountName, forKey: accountKey)
        d.set(s.inboxMailbox, forKey: inboxKey)
        d.set(s.sentMailbox, forKey: sentKey)
    }
}
