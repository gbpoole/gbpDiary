import Foundation

nonisolated enum TimesheetSummaryState: String, Equatable, Sendable {
    case pending, done, failed, unavailable
}

// The pure rules behind the Timesheet's cached per-project prose: what identifies a summary, when it is
// stale, and when it should be swept. Mirrors `EmailSummaryPlanning` / `EmailThreadSummaryPlanning`.
//
// The prompt only ever REPHRASES app-assembled rows (`TimesheetReport.phrasingPrompt`), so a change to the
// shared voice must refresh every cached paragraph — hence `AISummaryStyle.version` folded into
// `promptVersion`, exactly as the email prompts do it.
nonisolated enum TimesheetSummaryPlanning {
    /// Bump when the Timesheet's own prompt wording changes.
    /// 2: stopped feeding the model the internal "Unspecified work" label, which it narrated verbatim.
    static let promptBase = 2
    static var promptVersion: Int { promptBase + AISummaryStyle.version }

    /// How long a cached paragraph survives without being generated or shown.
    static let evictionWeeks = 5
    static var evictionInterval: TimeInterval { Double(evictionWeeks) * 7 * 24 * 60 * 60 }

    /// What the paragraph is derived from. Order-independent (the row order is a display concern) and
    /// sensitive to hours, comments and mined prose — so editing a comment refreshes the summary.
    static func fingerprint(node: TimesheetNode) -> String {
        var parts: [String] = []
        for row in node.subtreeRows {
            let details = row.details
                .map { "\($0.text)@\(hoursToken($0.hours))" }
                .sorted()
                .joined(separator: "|")
            parts.append("\(row.kind.rawValue):\(row.id.uuidString):\(hoursToken(row.hours)):\(details)")
        }
        for extract in node.subtreeExtracts {
            parts.append("x:\(extract.id.uuidString):\(extract.text.count):\(extract.title)")
        }
        return parts.sorted().joined(separator: ";")
    }

    /// A summary is wanted when there is prose-worthy material and no current, settled paragraph for it.
    /// `done` *and* `failed` count as settled for an unchanged fingerprint — a failure must not spin.
    static func needsSummary(hasContent: Bool, state: TimesheetSummaryState?, storedFingerprint: String?,
                             storedPromptVersion: Int?, fingerprint: String,
                             promptVersion: Int = promptVersion) -> Bool {
        guard hasContent else { return false }
        guard let state, let storedFingerprint, let storedPromptVersion else { return true }
        if storedFingerprint != fingerprint { return true }
        if storedPromptVersion != promptVersion { return true }
        switch state {
        case .pending: return true
        case .done, .failed, .unavailable: return false
        }
    }

    /// Swept five weeks after it was last generated or shown.
    static func isExpired(touchedAt: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(touchedAt) > evictionInterval
    }

    private static func hoursToken(_ hours: Double) -> String {
        String(format: "%.2f", hours)
    }
}
