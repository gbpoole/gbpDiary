import Foundation

// One logged-time record (a task time entry or a meeting), with its own date + project(s). Chat computes
// interval time totals from these — never from the RAG corpus (whose per-record dates are approximate and
// whose top-K is partial) and never by asking the model to sum.
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
}

nonisolated struct ChatTimeTotals: Equatable, Sendable {
    let perProject: [ChatProjectHours]   // descending by hours
    let overall: Double

    var isEmpty: Bool { overall <= 0 }

    /// Sum in-interval records (optionally restricted to a project), deduped by `sourceKey`. `overall` is
    /// the unique-record sum; a record linked to several projects contributes its hours to each of them.
    static func compute(records: [ChatTimeRecord], interval: Range<Date>,
                        projectName: String? = nil) -> ChatTimeTotals {
        var seen = Set<String>()
        var byProject: [String: Double] = [:]
        var order: [String] = []
        var overall = 0.0
        for record in records {
            guard interval.contains(record.date) else { continue }
            if let projectName,
               !record.projectNames.contains(where: { $0.caseInsensitiveCompare(projectName) == .orderedSame }) {
                continue
            }
            guard seen.insert(record.sourceKey).inserted else { continue }
            overall += record.hours
            let names = record.projectNames.isEmpty ? ["(no project)"] : record.projectNames
            for name in names {
                if byProject[name] == nil { order.append(name) }
                byProject[name, default: 0] += record.hours
            }
        }
        let perProject = order.map { ChatProjectHours(name: $0, hours: byProject[$0] ?? 0) }
            .sorted { $0.hours != $1.hours ? $0.hours > $1.hours : $0.name < $1.name }
        return ChatTimeTotals(perProject: perProject, overall: overall)
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
}
