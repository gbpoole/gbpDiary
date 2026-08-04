import Foundation

// On-device AI email summaries. Everything here is pure/testable except the model call, which is
// isolated behind `EmailSummarizing` (implemented by FoundationModelsSummarizer). No networking —
// the body is read from local Mail and summarized by the on-device model; only the summary is stored.

enum EmailSummaryState: String {
    case pending       // needs a summary
    case done          // summarized
    case failed        // body missing / model errored — skipped by the auto pass (manual retry resets)
    case unavailable   // on-device model unavailable on this Mac
}

/// A person known to the app, passed into the summariser so it can use short names and recognise "you".
struct SummaryPerson: Equatable {
    let name: String
    let emails: [String]
}

/// System-supplied context that augments the prompt: who the user is, the other party, the direction,
/// and a roster of known people (so addresses/full names collapse to short known names).
struct SummaryContext: Equatable {
    var me: SummaryPerson?          // the user (AppSettingsStore.myPersonID → Person)
    var other: SummaryPerson?       // the email's resolved other party (EmailMessage.person)
    var directionIsSent: Bool       // true = the user sent this email
    var roster: [SummaryPerson]     // known people (capped), for short-name resolution

    static let empty = SummaryContext(me: nil, other: nil, directionIsSent: false, roster: [])
}

/// The instructions + prompt handed to the on-device model.
enum EmailSummaryPrompt {
    /// Bump when the instructions/prompt change so stored summaries auto-refresh (see EmailSummaryPlanning).
    static let promptVersion = 1

    /// System instructions: identity-aware, concise, factual, no preamble/markdown.
    static let instructions = """
    You write a one- or two-sentence summary of an email for the reader's daily diary. Rules:
    • Refer to the reader (identified as "you" below) as "you" — never restate their name, title, or affiliation.
    • Use people's short/known names from the provided roster; never include titles, affiliations, or signatures.
    • Capture the gist and any request, decision, deadline, or action; ≤ ~40 words.
    • Be factual and concise. No greeting, preamble, sign-off, or markdown — output only the summary sentence(s).
    """

    /// Longest body slice fed to the model (keeps inference fast and within context).
    static let maxBodyChars = 6000
    /// Longest roster fed to the model (name ↔ emails), to keep the prompt small.
    static let maxRoster = 40

    /// Builds the user prompt: identity + direction + roster context, then subject + clamped body.
    static func build(context: SummaryContext, subject: String, body: String) -> String {
        var lines: [String] = []
        if let me = context.me {
            let addrs = me.emails.isEmpty ? "" : " (your addresses: \(me.emails.joined(separator: ", ")))"
            lines.append("You are \(me.name)\(addrs). Refer to yourself as \"you\".")
        }
        if let other = context.other {
            let addr = other.emails.first.map { " <\($0)>" } ?? ""
            lines.append(context.directionIsSent
                ? "You sent this email to \(other.name)\(addr)."
                : "You received this email from \(other.name)\(addr).")
        } else {
            lines.append(context.directionIsSent ? "You sent this email." : "You received this email.")
        }
        let roster = context.roster.prefix(maxRoster)
        if !roster.isEmpty {
            let entries = roster.map { p -> String in
                p.emails.first.map { "\(p.name) <\($0)>" } ?? p.name
            }
            lines.append("Known people: \(entries.joined(separator: "; "))")
        }
        lines.append("")
        lines.append("Subject: \(subject.isEmpty ? "(no subject)" : subject)")
        lines.append("")
        lines.append(clampBody(body))
        return lines.joined(separator: "\n")
    }

    /// Trims and caps the body length (prefix) so long threads/signatures don't blow the context.
    static func clampBody(_ body: String, limit: Int = maxBodyChars) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > limit ? String(trimmed.prefix(limit)) : trimmed
    }
}

/// Builds a compact, ordered, de-duplicated known-people roster for the prompt: the other party and
/// project-mates first (most likely to be referenced), then the rest alphabetically, capped.
enum EmailSummaryRoster {
    struct Candidate: Equatable {
        let id: UUID
        let name: String
        let emails: [String]
        let isPriority: Bool     // other party or shares a project with the email
    }

    static func build(_ candidates: [Candidate], limit: Int = EmailSummaryPrompt.maxRoster) -> [SummaryPerson] {
        var seen = Set<UUID>()
        let ordered = candidates
            .sorted { a, b in
                if a.isPriority != b.isPriority { return a.isPriority && !b.isPriority }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            .filter { seen.insert($0.id).inserted }
            .prefix(limit)
        return ordered.map { SummaryPerson(name: $0.name, emails: $0.emails) }
    }
}

/// Normalises the model's output for display: trim, collapse internal whitespace, cap length.
enum EmailSummaryText {
    static let maxChars = 400

    static func clean(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if t.count > maxChars {
            t = String(t.prefix(maxChars)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return t
    }
}

/// Whether the auto pass should summarise an email: non-dismissed AND (still pending, OR previously
/// done with a stale prompt version — so tuning the prompt re-summarises everything).
enum EmailSummaryPlanning {
    static func needsSummary(state: EmailSummaryState, dismissed: Bool,
                             version: Int = EmailSummaryPrompt.promptVersion,
                             current: Int = EmailSummaryPrompt.promptVersion) -> Bool {
        guard !dismissed else { return false }
        if state == .pending { return true }
        if state == .done && version < current { return true }
        return false
    }
}

enum EmailSummaryError: Error, Equatable {
    case modelUnavailable
    case emptyBody
}

/// The on-device summariser, isolated so orchestration is testable with a stub.
protocol EmailSummarizing {
    var isAvailable: Bool { get }
    func summarize(context: SummaryContext, subject: String, body: String) async throws -> String
}
