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

/// The instructions + prompt handed to the on-device model.
enum EmailSummaryPrompt {
    /// System instructions: concise, factual, no preamble/markdown.
    static let instructions = """
    You summarise an email in one or two short sentences for a busy professional's daily diary. \
    Capture the gist and any request, decision, deadline, or action. Be factual and concise. \
    Do not add a greeting, preamble, or markdown — output only the summary sentence(s).
    """

    /// Longest body slice fed to the model (keeps inference fast and within context).
    static let maxBodyChars = 6000

    /// Builds the user prompt from the envelope + a length-capped body.
    static func build(subject: String, from: String, body: String) -> String {
        """
        Subject: \(subject.isEmpty ? "(no subject)" : subject)
        From: \(from)

        \(clampBody(body))
        """
    }

    /// Trims and caps the body length (prefix) so long threads/signatures don't blow the context.
    static func clampBody(_ body: String, limit: Int = maxBodyChars) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > limit ? String(trimmed.prefix(limit)) : trimmed
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

/// Whether the auto pass should summarise an email (non-dismissed and still pending).
enum EmailSummaryPlanning {
    static func needsSummary(state: EmailSummaryState, dismissed: Bool) -> Bool {
        !dismissed && state == .pending
    }
}

enum EmailSummaryError: Error, Equatable {
    case modelUnavailable
    case emptyBody
}

/// The on-device summariser, isolated so orchestration is testable with a stub.
protocol EmailSummarizing {
    var isAvailable: Bool { get }
    func summarize(subject: String, from: String, body: String) async throws -> String
}
