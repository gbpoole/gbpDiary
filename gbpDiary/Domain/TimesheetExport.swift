import Foundation

// The Timesheet as a DOCUMENT: the same report, rendered as markdown you can paste into an email, a report,
// or an Obsidian note. Pure and testable — the on-screen layout is a view of this, not the other way round.
//
// The export is the complete record: unlike the screen (which clips each detail and extract to one line and
// collapses the rows), it carries every row, every comment, and every mined extract in full.
nonisolated enum TimesheetExport {

    /// `# Timesheet — 5 Jan 2026 – 9 Jan 2026`, the totals, then one section per project.
    /// `contentDirectory`, when given, adds a line pointing at the markdown tree written beside this file.
    static func composeMarkdown(report: TimesheetReport, ledger: LedgerResult, periodLabel: String,
                                prose: [UUID: String] = [:],
                                contentDirectory: String? = nil) -> String {
        var out: [String] = ["# Timesheet — \(periodLabel)", ""]

        out.append("**Total:** \(TimeFormat.hours(ledger.grandTotal)) · \(TimeFormat.days(ledger.grandTotal))")
        if ledger.overtime > 0 {
            out.append("**Overtime:** \(TimeFormat.hours(ledger.overtime)) (included in the total)")
        }
        let overLogged = report.totalOwnHours - ledger.grandTotal
        if overLogged > 0.05 {
            out.append("**Over-logged:** +\(TimeFormat.hours(overLogged)) — activity inside focus blocks "
                       + "exceeds their capacity, so the rows below sum higher than the total.")
        }
        if let contentDirectory {
            out.append("_Full content: [\(contentDirectory)/README.md](\(contentDirectory)/README.md)_")
        }
        out.append("")

        guard !report.isEmpty else {
            out.append("_No logged time in this period._")
            return out.joined(separator: "\n")
        }
        for node in report.nodes {
            out.append(contentsOf: section(node, depth: 0, prose: prose))
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private static func section(_ node: TimesheetNode, depth: Int, prose: [UUID: String]) -> [String] {
        let heading = String(repeating: "#", count: min(depth + 2, 6))
        var out: [String] = ["\(heading) \(node.headerLine)"]
        if !node.children.isEmpty {
            out.append("_Including subprojects: \(TimeFormat.hours(node.subtreeHours))._")
        }
        out.append("")
        if let text = prose[node.id], !text.isEmpty {
            out.append(text)
            out.append("")
        }
        for group in node.groups {
            out.append("**\(group.title)**")
            out.append("")
            for row in group.rows {
                out.append("- \(row.bulletLabel)\(row.status.map { " — \($0)" } ?? "")")
                for detail in row.details {
                    out.append("    - \(detail.label)")
                }
            }
            out.append("")
        }
        if !node.extracts.isEmpty {
            out.append("**Notes**")
            out.append("")
            for extract in node.extracts {
                out.append("- **\(extract.title)** — \(extract.text)")
            }
            out.append("")
        }
        for child in node.children {
            out.append(contentsOf: section(child, depth: depth + 1, prose: prose))
        }
        return out
    }

    /// `5 Jan 2026 – 9 Jan 2026` for a half-open whole-day interval (the last day shown is inclusive).
    static func periodLabel(_ interval: Range<Date>, calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMM yyyy"
        let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.upperBound) ?? interval.upperBound
        let start = f.string(from: interval.lowerBound)
        let end = f.string(from: lastDay)
        return start == end ? start : "\(start) – \(end)"
    }

    /// A safe file base name, mirroring `MinutesExport.exportBaseName`.
    static func fileName(periodLabel: String) -> String {
        folderName(periodLabel: periodLabel) + ".md"
    }

    /// The export is a FOLDER, not a loose file: `NSSavePanel` grants access to exactly the URL you name,
    /// so a sibling write (the JSON) or a sibling directory (the content tree) is refused by the sandbox —
    /// which is precisely what happened. Everything therefore lives inside the one chosen URL.
    static func folderName(periodLabel: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let cleaned = String(periodLabel.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Timesheet" : "Timesheet \(cleaned)"
    }

    /// Fixed names inside the export folder, so an agent given the folder knows where everything is.
    static let summaryFileName = "summary.md"
    static let dataFileName = "data.json"
    static let contentDirectoryName = "content"
}
