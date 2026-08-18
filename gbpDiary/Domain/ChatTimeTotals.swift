import Foundation

// Renders a Chat time-report answer from the canonical `TimeLedger` — Chat no longer computes time itself;
// it filters the ledger's per-project result to the asked scope and renders it deterministically (the app
// IS the answer for a time report, so it never depends on the model).
nonisolated struct ChatTimeTotals: Equatable, Sendable {
    let perProject: [LedgerProjectHours]   // descending by hours
    let overall: Double

    var isEmpty: Bool { overall <= 0 }

    /// The ledger's per-project result, optionally restricted to one project (case-insensitive).
    static func from(ledger: LedgerResult, projectName: String?) -> ChatTimeTotals {
        let filtered = projectName.map { pn in
            ledger.perProject.filter { $0.name.caseInsensitiveCompare(pn) == .orderedSame }
        } ?? ledger.perProject
        return ChatTimeTotals(perProject: filtered, overall: filtered.reduce(0) { $0 + $1.hours })
    }

    /// A deterministic, authoritative natural-language answer. `intervalLabel` nil = all time;
    /// `projectName` set = single-project phrasing.
    func report(intervalLabel: String?, projectName: String?) -> String {
        let over = intervalLabel.map { " over \($0)" } ?? ""
        guard !isEmpty else { return "No time is logged\(over)." }
        if projectName != nil, perProject.count <= 1, let p = perProject.first {
            return "You logged \(Self.hoursText(p.hours)) on \(p.name)\(over) — active in \(Self.weeksText(p.distinctWeeks))."
        }
        let lines = perProject.map {
            "• \($0.name) — \(Self.hoursText($0.hours)), active in \(Self.weeksText($0.distinctWeeks))"
        }
        return "Time logged\(over):\n" + lines.joined(separator: "\n") + "\nTotal — \(Self.hoursText(overall))"
    }

    /// A diagnostic answer for when nothing matched — reveals the scope, the window, and whether any time
    /// exists at all, so an empty result is explainable rather than opaque. `overallHours` = the same scope's
    /// all-time total (from the ledger over a nil interval).
    static func emptyReport(interval: Range<Date>?, intervalLabel: String?, projectName: String?,
                            overallHours: Double, calendar: Calendar) -> String {
        let over = intervalLabel.map { " for \($0)" } ?? ""
        let scope = projectName.map { " on \($0)" } ?? " on any project"
        let line = "No time is logged\(scope)\(over)."
        guard overallHours > 0 else { return line + " (No logged time was found at all.)" }

        var diag = ["\(hoursText(overallHours)) logged in total"]
        if let interval {
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_US_POSIX"); fmt.dateFormat = "d MMM yyyy"; fmt.calendar = calendar
            diag.append("window \(fmt.string(from: interval.lowerBound))–\(fmt.string(from: interval.upperBound))")
        }
        return line + " (" + diag.joined(separator: "; ") + ".)"
    }

    /// An authoritative prompt block instructing the model to report these exact figures (nil when empty).
    func authoritativeBlock(intervalLabel: String) -> String? {
        guard !isEmpty else { return nil }
        let parts = perProject.map { "\($0.name) — \(Self.hoursText($0.hours))" }
        let breakdown = parts.isEmpty ? "" : parts.joined(separator: "; ") + "; "
        return "Computed time totals for \(intervalLabel) (authoritative — report these exact figures): "
            + breakdown + "Total — \(Self.hoursText(overall))"
    }

    static func hoursText(_ hours: Double) -> String { TimeFormat.hours(hours) }
    static func weeksText(_ weeks: Int) -> String { weeks == 1 ? "1 week" : "\(weeks) weeks" }
    static func daysText(_ hours: Double) -> String { TimeFormat.days(hours) }
}
