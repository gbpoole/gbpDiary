import Foundation

// One logged-time record (a task time entry, standalone email time, or a meeting), with its own date +
// project(s). Chat computes time reports from these — never from the RAG corpus (whose per-record dates
// are approximate and whose top-K is partial) and never by asking the model to sum. Dates are already
// weekend-folded upstream (ChatView.timeRecords), so week bucketing attributes weekend work to Friday.
nonisolated struct ChatTimeRecord: Equatable, Sendable {
    let sourceKey: String        // stable per underlying record (dedupe)
    let date: Date
    let hours: Double
    let projectNames: [String]   // display case; empty = unassigned

    init(sourceKey: String, date: Date, hours: Double, projectNames: [String]) {
        self.sourceKey = sourceKey
        self.date = date
        self.hours = hours
        self.projectNames = projectNames
    }
}

nonisolated struct ChatProjectHours: Equatable, Sendable {
    let name: String
    let hours: Double
    let distinctWeeks: Int   // number of distinct calendar weeks with any logged time on this project

    init(name: String, hours: Double, distinctWeeks: Int = 0) {
        self.name = name
        self.hours = hours
        self.distinctWeeks = distinctWeeks
    }
}

nonisolated struct ChatTimeTotals: Equatable, Sendable {
    let perProject: [ChatProjectHours]   // descending by hours
    let overall: Double

    var isEmpty: Bool { overall <= 0 }

    /// Sum records (optionally restricted to an interval and/or a project), deduped by `sourceKey`. A nil
    /// interval means **all time**. `overall` is the unique-record hour sum; a record linked to several
    /// projects contributes its hours (and its week) to each. `distinctWeeks` counts distinct calendar
    /// weeks with any logged time on that project.
    static func compute(records: [ChatTimeRecord], interval: Range<Date>? = nil,
                        projectName: String? = nil, calendar: Calendar = .current) -> ChatTimeTotals {
        var seen = Set<String>()
        var byProject: [String: Double] = [:]
        var weeksByProject: [String: Set<String>] = [:]
        var order: [String] = []
        var overall = 0.0
        for record in records {
            if let interval, !interval.contains(record.date) { continue }
            if let projectName,
               !record.projectNames.contains(where: { $0.caseInsensitiveCompare(projectName) == .orderedSame }) {
                continue
            }
            guard seen.insert(record.sourceKey).inserted else { continue }
            overall += record.hours
            let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: record.date)
            let weekKey = "\(comps.yearForWeekOfYear ?? 0)-\(comps.weekOfYear ?? 0)"
            let names = record.projectNames.isEmpty ? ["(no project)"] : record.projectNames
            for name in names {
                if byProject[name] == nil { order.append(name) }
                byProject[name, default: 0] += record.hours
                weeksByProject[name, default: []].insert(weekKey)
            }
        }
        let perProject = order
            .map { ChatProjectHours(name: $0, hours: byProject[$0] ?? 0, distinctWeeks: weeksByProject[$0]?.count ?? 0) }
            .sorted { $0.hours != $1.hours ? $0.hours > $1.hours : $0.name < $1.name }
        return ChatTimeTotals(perProject: perProject, overall: overall)
    }

    /// A deterministic, authoritative natural-language answer — the app IS the answer for a time report,
    /// so it never depends on the model. `intervalLabel` nil = all time; `projectName` set = single-project.
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

    /// An authoritative prompt block instructing the model to report these exact figures (nil when empty).
    func authoritativeBlock(intervalLabel: String) -> String? {
        guard !isEmpty else { return nil }
        let parts = perProject.map { "\($0.name) — \(Self.hoursText($0.hours))" }
        let breakdown = parts.isEmpty ? "" : parts.joined(separator: "; ") + "; "
        return "Computed time totals for \(intervalLabel) (authoritative — report these exact figures): "
            + breakdown + "Total — \(Self.hoursText(overall))"
    }

    static func hoursText(_ hours: Double) -> String {
        let rounded = (hours * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded))h" : String(format: "%.1fh", rounded)
    }

    static func weeksText(_ weeks: Int) -> String { weeks == 1 ? "1 week" : "\(weeks) weeks" }

    /// Full-time-equivalent days from hours (a working day = 7.6h), single-sourced from `DurationUnit`.
    static func daysText(_ hours: Double) -> String {
        let days = hours / DurationUnit.d.hoursPerUnit
        let rounded = (days * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded))d" : String(format: "%.1fd", rounded)
    }
}
