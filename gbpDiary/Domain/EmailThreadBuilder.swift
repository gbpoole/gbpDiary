import Foundation
import SwiftData

// A thread of a day's emails sharing a subject (ignoring Re:/Fwd:) and the same other party. A
// conversation's sent and received messages unite because a Sent message's `fromAddress` stores the
// recipient — the same party as the received sender. Pure data (no SwiftUI); the summary line is supplied
// by the view from the EmailThreadSummary store, falling back to the latest message's per-email summary.
struct EmailThread: Identifiable {
    let key: String
    let messages: [EmailMessage]   // sorted latest-first
    var synthesizedSummary: String?   // whole-thread day summary (set by the view); nil → use `summary`

    init(key: String, messages: [EmailMessage], synthesizedSummary: String? = nil) {
        self.key = key
        self.messages = messages
        self.synthesizedSummary = synthesizedSummary
    }

    var id: String { key }
    var latest: EmailMessage { messages[0] }
    var subject: String { latest.subject.isEmpty ? "(no subject)" : latest.subject }
    var person: Person? { messages.first(where: { $0.person != nil })?.person }
    var fromName: String? { latest.fromName }
    var fromAddress: String { latest.fromAddress }
    var direction: EmailDirection { latest.direction }
    var count: Int { messages.count }
    var date: Date { latest.date }

    /// The line shown for the thread: the synthesized whole-thread summary when ready, else the latest
    /// message's per-email summary (so a single-message thread just shows its own summary).
    var summary: String? { synthesizedSummary ?? latest.summary }
    /// Still generating when the thread summary is absent and the latest message is mid-summarise.
    var isSummarizing: Bool { synthesizedSummary == nil && latest.isSummarizing }

    var sentCount: Int { messages.filter { $0.direction == .sent }.count }
    var receivedCount: Int { messages.filter { $0.direction == .inbox }.count }

    /// Thread importance = the highest across its messages (setting it writes them all — see the row).
    var importance: EmailImportance {
        messages.map(\.importance).max(by: { $0.rank < $1.rank }) ?? .low
    }

    /// To-dos made from any message in the thread.
    var tasks: [Task] { messages.flatMap(\.tasks) }
    var taskCount: Int { tasks.count }
    var hasOpenTasks: Bool { tasks.contains(where: \.isOpen) }

    /// Union of projects across the thread's messages (de-duplicated, order preserved).
    var projects: [Project] {
        var seen = Set<PersistentIdentifier>()
        var out: [Project] = []
        for m in messages {
            for p in m.projects where seen.insert(p.persistentModelID).inserted { out.append(p) }
        }
        return out
    }
}

// Groups a set of emails into threads by `EmailThreading.threadKey` (normalized subject + other party).
// Callers pre-filter the input (received-only for the diary Email section, block-scoped for the activity
// digest, day-scoped for the summary driver). @MainActor because it reads `@Model` relationships.
@MainActor
enum EmailThreadBuilder {
    static func threads(from emails: [EmailMessage]) -> [EmailThread] {
        let groups = Dictionary(grouping: emails) { email in
            EmailThreading.threadKey(subject: email.subject,
                                     party: email.person?.id.uuidString ?? email.fromAddress)
        }
        return groups.map { key, msgs in
            EmailThread(key: key, messages: msgs.sorted { $0.date > $1.date })
        }
    }

    /// The thread key an email belongs to — so a caller can look up its stored thread summary.
    static func threadKey(for email: EmailMessage) -> String {
        EmailThreading.threadKey(subject: email.subject,
                                 party: email.person?.id.uuidString ?? email.fromAddress)
    }

    /// The stored whole-thread day summary for a multi-message thread (nil for a single-message thread or
    /// until the driver has generated it — the caller then falls back to the message's own summary).
    static func summaryText(for thread: EmailThread, in summaries: [EmailThreadSummary],
                            calendar: Calendar = .current) -> String? {
        guard thread.count > 1 else { return nil }
        let dayStart = calendar.startOfDay(for: thread.date)
        return summaries.first {
            $0.threadKey == thread.key && $0.dayStart == dayStart
                && $0.summaryState == EmailSummaryState.done.rawValue
        }?.text
    }
}
