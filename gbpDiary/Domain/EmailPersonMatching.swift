import Foundation

// Resolves an email's "other party" (Inbox = sender, Sent = recipient) to an existing Person by
// address alone (never by name — display names are unreliable). Pure and testable; the view layer
// maps its People to `[PersonRef]` and applies the result when upserting fetched emails.
enum EmailPersonMatching {
    /// The id of the Person whose `emails` contain `address` (case-insensitive), else nil.
    /// Blank/whitespace addresses never match.
    static func personID(forAddress address: String, in people: [PersonRef]) -> UUID? {
        let needle = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        return people.first { person in
            person.emails.contains { $0.caseInsensitiveCompare(needle) == .orderedSame }
        }?.id
    }
}
