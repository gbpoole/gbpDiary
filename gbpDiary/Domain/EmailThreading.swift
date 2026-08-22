import Foundation

// Groups the day's emails into threads on the diary page. A thread unites messages that share a
// conversation **subject** (ignoring Re:/Fwd: prefixes) — including a multi-party exchange, where the
// "other party" varies message to message. We can't use RFC References/In-Reply-To headers (envelope-only
// fetch), so this is standard subject threading, scoped to the day by the caller's filter. Pure so the
// keying is testable; the view groups its EmailMessages by `threadKey`.
enum EmailThreading {
    private static let replyPrefixes = ["re:", "fwd:", "fw:"]

    /// Subject stripped of leading Re:/Fwd:/Fw: prefixes (repeated) and trimmed, **preserving case** — for
    /// display (the thread's clean subject).
    static func strippedSubject(_ subject: String) -> String {
        var s = subject.trimmingCharacters(in: .whitespaces)
        var changed = true
        while changed {
            changed = false
            for prefix in replyPrefixes where s.lowercased().hasPrefix(prefix) {
                s = String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                changed = true
            }
        }
        return s
    }

    /// The stripped subject lowercased — the keying/matching form.
    static func normalizedSubject(_ subject: String) -> String { strippedSubject(subject).lowercased() }

    /// A thread key from the conversation subject (Re:/Fwd: stripped). A multi-party exchange on one
    /// subject stays a single thread even though each message's "other party" differs. Empty/no-subject
    /// mail shares no meaningful subject, so it falls back to the party to avoid merging unrelated blanks.
    static func threadKey(subject: String, party: String) -> String {
        let subj = normalizedSubject(subject)
        guard !subj.isEmpty else { return "∅|\(party.trimmingCharacters(in: .whitespaces).lowercased())" }
        return subj
    }
}
