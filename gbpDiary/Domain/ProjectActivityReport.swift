import Foundation

// A per-project report that pairs the canonical time (hours / days / distinct active weeks, from TimeLedger)
// with a deterministic "what was done" narrative (meetings, completed tasks, logged comments, emails). Built
// once (ProjectActivityProjection) and shared by the Timesheet and Chat. Facts are app-owned; the on-device
// model may only rephrase `render()`/`phrasingPrompt` output — it never invents.
nonisolated struct ProjectActivitySection: Equatable, Sendable {
    let projectName: String
    let hours: Double
    let distinctWeeks: Int
    let items: [ChatActivityItem]   // "what was done", ordered for display

    /// De-duplicated click-through sources, in item order.
    var sources: [ChatSourceReference] {
        var seen = Set<ChatSourceKey>()
        return items.compactMap(\.source).filter { seen.insert($0.key).inserted }
    }

    var headerLine: String {
        "\(projectName) — \(TimeFormat.hours(hours)) · \(TimeFormat.days(hours)) · \(ChatTimeTotals.weeksText(distinctWeeks))"
    }
}

nonisolated struct ProjectActivityReport: Equatable, Sendable {
    let sections: [ProjectActivitySection]   // descending by hours
    let interval: Range<Date>?

    var isEmpty: Bool { sections.isEmpty }

    func section(matching projectName: String) -> ProjectActivitySection? {
        sections.first { $0.projectName.caseInsensitiveCompare(projectName) == .orderedSame }
    }

    /// The deterministic factual block: each project's header line followed by its labelled bullets.
    func render() -> String {
        sections.map { s in
            let bullets = s.items.map { "• \($0.label)" }.joined(separator: "\n")
            return bullets.isEmpty ? s.headerLine : "\(s.headerLine)\n\(bullets)"
        }.joined(separator: "\n\n")
    }

    /// Just the "what was done" bullets grouped under each project name, with no time header — used to
    /// append under a time report that already states the hours. Optionally scoped to one project. Empty
    /// string when there is no narrative to show.
    func narrativeBlock(projectName: String? = nil) -> String {
        let scoped: [ProjectActivitySection]
        if let projectName {
            scoped = section(matching: projectName).map { [$0] } ?? []   // named but unmatched → nothing
        } else {
            scoped = sections
        }
        return scoped.compactMap { s -> String? in
            guard !s.items.isEmpty else { return nil }
            let bullets = s.items.map { "• \($0.label)" }.joined(separator: "\n")
            return "\(s.projectName):\n\(bullets)"
        }.joined(separator: "\n\n")
    }

    /// The strict rephrase-only instruction for turning one project's items into prose (Summarise ✨).
    static func phrasingPrompt(section: ProjectActivitySection) -> String {
        let block = section.items.map { "• \($0.label)" }.joined(separator: "\n")
        return """
        Summarise the following list of work on the project "\(section.projectName)" into a brief \
        paragraph. Use ONLY these items — do not add, infer, embellish, or omit anything. Keep it concise. \
        \(AISummaryStyle.inline)

        \(block)
        """
    }
}
