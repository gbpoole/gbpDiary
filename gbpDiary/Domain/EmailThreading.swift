import Foundation

// Groups the day's emails into threads on the diary page. A thread unites messages that share a
// subject (ignoring Re:/Fwd: prefixes) and the same "other party". Pure so the keying is testable;
// the view groups its EmailMessages by `threadKey`.
enum EmailThreading {
    private static let replyPrefixes = ["re:", "fwd:", "fw:"]

    /// Subject stripped of leading Re:/Fwd:/Fw: prefixes (repeated), trimmed and lowercased for keying.
    static func normalizedSubject(_ subject: String) -> String {
        var s = subject.trimmingCharacters(in: .whitespaces)
        var changed = true
        while changed {
            changed = false
            for prefix in replyPrefixes where s.lowercased().hasPrefix(prefix) {
                s = String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                changed = true
            }
        }
        return s.lowercased()
    }

    /// A thread key from the normalized subject + the other party (person id or address, lowercased).
    static func threadKey(subject: String, party: String) -> String {
        "\(normalizedSubject(subject))|\(party.trimmingCharacters(in: .whitespaces).lowercased())"
    }
}
