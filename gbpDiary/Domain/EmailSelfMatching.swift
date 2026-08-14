import Foundation

// Excludes mailing-list loopbacks. When you send an email to a list you're on (or CC yourself), a copy
// comes back to your Inbox with *you* as the sender. Such received (inbox) messages whose sender is one
// of your own addresses are dropped — the Sent copy already represents the email with the right
// direction/recipient. "Your own addresses" are the emails of the configured **Me** person, so this
// catches identities the Mail account itself doesn't list (e.g. a work address on a Gmail account).
enum EmailSelfMatching {
    /// Normalized "my" addresses: trimmed, lowercased, non-empty.
    static func normalizedAddresses(_ emails: [String]) -> Set<String> {
        Set(emails
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty })
    }

    /// True when a *received* (inbox) email's sender is one of my own addresses — a loopback to exclude.
    /// Sent mail is never a loopback (it's the real outgoing copy), so it always returns false.
    static func isInboxFromSelf(direction: EmailDirection, fromAddress: String,
                                myAddresses: Set<String>) -> Bool {
        guard direction == .inbox else { return false }
        let address = fromAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !address.isEmpty && myAddresses.contains(address)
    }
}
