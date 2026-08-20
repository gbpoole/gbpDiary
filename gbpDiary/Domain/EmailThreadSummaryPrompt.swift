import Foundation

// Pure pieces for the synthesized whole-thread day summary. The thread summary is generated on-device
// over the member emails' EXISTING per-email summaries (app-owned facts) — never raw bodies — so it is
// cheap, stays on device, and only rephrases what the app already produced. Voice comes from the shared
// `AISummaryStyle`. The stored summary (an `EmailThreadSummary` @Model) is regenerated when the thread's
// membership or any member's per-email summary version changes (via the fingerprint) or the prompt bumps.

/// One member message as fed to the thread-summary prompt: its direction, time label, and per-email summary.
nonisolated struct ThreadMessageLine: Equatable, Sendable {
    let directionIsSent: Bool
    let time: String        // preformatted "HH:MM" (the caller formats; keeps this pure/testable)
    let summary: String
}

nonisolated enum EmailThreadSummaryPrompt {
    /// Bump `base` when the thread-specific instructions change; `AISummaryStyle.version` is folded in so a
    /// shared-voice change also refreshes stored thread summaries.
    private static let base = 1
    static var promptVersion: Int { base + AISummaryStyle.version }

    static let instructions = """
    You write a one- or two-sentence summary of an email conversation for the reader's daily diary, from the
    per-message summaries provided. Rules:
    • Combine the messages into a single coherent account of what happened in the conversation that day.
    • Use the participants' short names; capture any request, decision, deadline, or action.
    • Do not list the messages one by one; write a flowing summary of the exchange.
    \(AISummaryStyle.directive)
    """

    /// The user prompt: subject + participants, then each message as "(sent/received <time>) <summary>".
    static func build(subject: String, participants: [String], messages: [ThreadMessageLine]) -> String {
        var lines: [String] = []
        lines.append("Subject: \(subject.isEmpty ? "(no subject)" : subject)")
        if !participants.isEmpty { lines.append("Participants: \(participants.joined(separator: ", "))") }
        lines.append("")
        lines.append("Messages (oldest first):")
        for m in messages {
            let dir = m.directionIsSent ? "sent" : "received"
            lines.append("• (\(dir) \(m.time)) \(m.summary)")
        }
        return lines.joined(separator: "\n")
    }
}

nonisolated enum EmailThreadSummaryFingerprint {
    /// A stable signature of the summary inputs: each member's id + the per-email summary version it was
    /// built from, sorted and joined. Changes when a member joins/leaves or any member re-summarises.
    static func make(_ members: [(id: UUID, summaryVersion: Int)]) -> String {
        members.map { "\($0.id.uuidString):\($0.summaryVersion)" }.sorted().joined(separator: "|")
    }
}

nonisolated enum EmailThreadSummaryPlanning {
    /// Whether the stored thread summary must be (re)generated. False only when it is settled
    /// (`done`/`failed`), its fingerprint matches the current inputs, and its prompt version is current —
    /// so we neither re-run a good summary nor hammer a genuine failure with the same inputs.
    static func needsSummary(state: EmailSummaryState?, storedFingerprint: String?, fingerprint: String,
                             storedVersion: Int,
                             currentVersion: Int = EmailThreadSummaryPrompt.promptVersion) -> Bool {
        let settled = (state == .done || state == .failed)
        if settled, storedFingerprint == fingerprint, storedVersion >= currentVersion { return false }
        return true
    }
}
