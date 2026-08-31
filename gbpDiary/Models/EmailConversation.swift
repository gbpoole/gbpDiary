import Foundation
import SwiftData

// A cross-day email conversation, threaded by the reply graph (`EmailThreadGraph`). It OWNS the
// cross-cutting state that previously lived on individual messages — triage state, project(s), the other
// party, importance, and logged time — so those are set once for the whole conversation and new mail joins
// it consistently. Emails link via `EmailMessage.conversation`; day views surface each day's slice. A
// rebuildable projection of its messages (safe to wipe and re-derive). All properties default for
// lightweight migration.
//
// (Named `EmailConversation` to avoid colliding with the ephemeral display `struct EmailThread` in
// `EmailThreadBuilder`; this is the persistent entity.)
@Model final class EmailConversation {
    @Attribute(.unique) var id: UUID = UUID()
    // Stable identity from `EmailThreadGraph` (reply-graph root Message-ID, or a subject fallback).
    var threadKey: String = ""

    // Triage state (mirrors EmailMessage's tri-state), applied to the whole conversation.
    var dismissed: Bool = false
    var accepted: Bool = false
    var triageState: EmailTriageState { .from(dismissed: dismissed, accepted: accepted) }
    func accept() { accepted = true; dismissed = false }
    func triageDismiss() { dismissed = true }
    func unclassify() { accepted = false; dismissed = false }

    // Manual importance (H/M/L, default Low) — same idiom as EmailMessage.importanceRaw/importance.
    var importanceRaw: String = EmailImportance.low.rawValue
    var importance: EmailImportance {
        get { EmailImportance(rawValue: importanceRaw) ?? .low }
        set { importanceRaw = newValue.rawValue }
    }
    var isImportant: Bool { importance != .low }

    // The resolved "other party" for the conversation (nullifies if the Person is deleted).
    var person: Person?
    // Projects this conversation is filed under.
    @Relationship(inverse: \Project.conversations) var projects: [Project] = []
    // Time logged against the conversation (counts toward the day/interval activity totals).
    @Relationship(deleteRule: .cascade, inverse: \TaskTimeEntry.conversation) var timeEntries: [TaskTimeEntry] = []
    // The messages belonging to this conversation (nullify on delete — the messages survive).
    @Relationship(deleteRule: .nullify, inverse: \EmailMessage.conversation) var messages: [EmailMessage] = []

    init(threadKey: String, id: UUID = UUID()) {
        self.id = id
        self.threadKey = threadKey
    }

    // MARK: - Display helpers (the entity replaces the ephemeral `struct EmailThread` in the views)

    var sortedMessages: [EmailMessage] { messages.sorted { $0.date > $1.date } }
    var latest: EmailMessage? { sortedMessages.first }
    var count: Int { messages.count }
    var date: Date { latest?.date ?? .distantPast }
    var subject: String {
        let s = latest?.subject ?? ""
        return s.isEmpty ? "(no subject)" : s
    }
    /// Subject with Re:/Fwd: stripped (case preserved) — for display.
    var displaySubject: String {
        let s = EmailThreading.strippedSubject(latest?.subject ?? "")
        return s.isEmpty ? "(no subject)" : s
    }
    var sentCount: Int { messages.filter { $0.direction == .sent }.count }
    var receivedCount: Int { messages.filter { $0.direction == .inbox }.count }
    /// The conversation's logged hours (its own time entries).
    var loggedHours: Double { timeEntries.reduce(0.0) { $0 + $1.duration.hoursNormalized } }
    /// To-dos made from any message in the conversation.
    var tasks: [Task] { messages.flatMap(\.tasks) }
    var taskCount: Int { tasks.count }
    var hasOpenTasks: Bool { tasks.contains(where: \.isOpen) }
    /// The latest message's per-message AI summary (fallback line until a synthesized summary is aligned).
    var latestMessageSummary: String? { latest?.summary }
    var isSummarizing: Bool { latest?.isSummarizing ?? false }
    var fromName: String? { latest?.fromName }
    var fromAddress: String { latest?.fromAddress ?? "" }
    /// Messages on a given calendar day (the day's slice), latest-first.
    func messages(on day: Date, calendar: Calendar = .current) -> [EmailMessage] {
        sortedMessages.filter { calendar.isDate($0.date, inSameDayAs: day) }
    }
}
