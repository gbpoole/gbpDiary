import Foundation

// The Timesheet's report: per project (nested, as projects nest), the canonical hours from `TimeLedger`
// paired with the rows that ACCOUNT for them.
//
// The model, once:
//   • A project's `ownHours` are the ledger's hours for that project — logged activities plus the net
//     (capacity − in-block logged) of the focus blocks it backs.
//   • Those hours are not a residue: every one of them belongs to a ROW. A focus block's net is real work
//     on the block's backing task, so it lands on that task's row like a logged entry does.
//   • INVARIANT: `rowsHours == ownHours` for every node. The headline the view shows is the ledger's own
//     `grandTotal`, and any difference from the sum of the rows is over-logging, reported explicitly —
//     never hidden by quietly dropping a bucket (the old report deleted "(no project)" by name).
//   • Rows carry one detail line per logged comment, plus at most ONE "Unspecified work" line stacking all
//     of that row's undescribed time, so an uncommented week reads as one line and not forty.
//   • `extracts` (mined note prose) is deliberately a SEPARATE field: the Timesheet reads it, Chat cannot,
//     so Chat's bounded prompt context can never be flooded by it.
//
// Facts are app-assembled; the on-device model may only rephrase `phrasingPrompt` output — never invent.

nonisolated enum TimesheetRowKind: String, Equatable, Sendable, CaseIterable {
    case task                  // a task that received time in the range
    case meeting               // a meeting held in the range
    case conversation          // an email conversation with logged time
    case completedNoTime       // completed in the range, nothing logged against it (0h)
    case unfiledConversation   // correspondence in the range that was never filed to a project (0h)

    /// The group heading a row sits under, in display order.
    var groupTitle: String {
        switch self {
        case .task: return "Tasks"
        case .meeting: return "Meetings"
        case .conversation: return "Communications"
        case .completedNoTime: return "Completed, no time logged"
        case .unfiledConversation: return "Not filed to a project"
        }
    }

    var groupOrder: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// Presence-only kinds carry no hours by construction, so they can never break the hours invariant.
    var isPresenceOnly: Bool { self == .completedNoTime || self == .unfiledConversation }
}

/// One line beneath a row: either a logged comment with its time, or the single stacked line for all of
/// that row's undescribed time.
nonisolated struct TimesheetDetail: Equatable, Sendable, Identifiable {
    let id: UUID
    let text: String
    let hours: Double
    let isUnspecified: Bool

    init(id: UUID = UUID(), text: String, hours: Double, isUnspecified: Bool = false) {
        self.id = id
        self.text = text
        self.hours = hours
        self.isUnspecified = isUnspecified
    }

    var label: String { hours > 0 ? "\(text) (\(TimeFormat.hours(hours)))" : text }
}

nonisolated struct TimesheetRow: Equatable, Sendable, Identifiable {
    let id: UUID                       // the underlying model's id
    let kind: TimesheetRowKind
    let title: String
    let hours: Double
    let date: Date                     // latest contributing date, weekend-folded (ordering)
    let status: String?                // "✓ 29 Sep" / "in progress"
    let badge: String?                 // "2 sent · 7 recv" / "[H]"
    let details: [TimesheetDetail]
    let source: ChatSourceReference?

    init(id: UUID, kind: TimesheetRowKind, title: String, hours: Double, date: Date,
         status: String? = nil, badge: String? = nil, details: [TimesheetDetail] = [],
         source: ChatSourceReference? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.hours = hours
        self.date = date
        self.status = status
        self.badge = badge
        self.details = details
        self.source = source
    }

    /// The narrative bullet — the single rendering shared by the deterministic report, the export, the
    /// model's rephrase prompt, and Chat's narrative block.
    var bulletLabel: String {
        let time = hours > 0 ? " (\(TimeFormat.hours(hours)))" : ""
        let mark = badge.map { " \($0)" } ?? ""
        switch kind {
        case .meeting: return "Meeting: \(title)\(time)"
        case .conversation, .unfiledConversation: return "Email: \(title)\(mark)\(time)"
        case .completedNoTime: return "Completed: \(title)"
        case .task:
            let done = status != nil
            return "\(done ? "Completed" : "Worked on"): \(title)\(time)"
        }
    }
}

/// Prose the app already holds — a meeting's minutes, a project-linked note — bounded and attributed.
/// Timesheet-only by construction (see the type comment).
nonisolated struct TimesheetExtract: Equatable, Sendable, Identifiable {
    let id: UUID
    let title: String
    let text: String
    let date: Date
    let source: ChatSourceReference?

    init(id: UUID, title: String, text: String, date: Date, source: ChatSourceReference? = nil) {
        self.id = id
        self.title = title
        self.text = text
        self.date = date
        self.source = source
    }
}

nonisolated struct TimesheetNode: Equatable, Sendable, Identifiable {
    let id: UUID                        // Project.id, or TimesheetReport.unattributedID
    let key: String                     // the ledger's project key
    let name: String
    let ownHours: Double                // the ledger's hours for THIS project alone
    let distinctWeeks: Int
    let rows: [TimesheetRow]            // hours-bearing rows; Σ hours == ownHours
    let unloggedRows: [TimesheetRow]    // 0h presence rows
    let extracts: [TimesheetExtract]
    let children: [TimesheetNode]
    let isUnattributed: Bool

    init(id: UUID, key: String, name: String, ownHours: Double, distinctWeeks: Int,
         rows: [TimesheetRow] = [], unloggedRows: [TimesheetRow] = [], extracts: [TimesheetExtract] = [],
         children: [TimesheetNode] = [], isUnattributed: Bool = false) {
        self.id = id
        self.key = key
        self.name = name
        self.ownHours = ownHours
        self.distinctWeeks = distinctWeeks
        self.rows = rows
        self.unloggedRows = unloggedRows
        self.extracts = extracts
        self.children = children
        self.isUnattributed = isUnattributed
    }

    /// The hours the rows account for — equal to `ownHours` (the invariant).
    var rowsHours: Double { rows.reduce(0) { $0 + $1.hours } }

    /// This project plus everything beneath it.
    var subtreeHours: Double { ownHours + children.reduce(0) { $0 + $1.subtreeHours } }

    /// Pre-order: self, then descendants.
    var selfAndDescendants: [TimesheetNode] { [self] + children.flatMap(\.selfAndDescendants) }

    var hasContent: Bool { !rows.isEmpty || !unloggedRows.isEmpty || !extracts.isEmpty }

    /// Every row in the subtree, so a parent's prose covers the work done beneath it (not just its own).
    var subtreeRows: [TimesheetRow] {
        selfAndDescendants.flatMap { $0.rows + $0.unloggedRows }
    }

    var subtreeExtracts: [TimesheetExtract] { selfAndDescendants.flatMap(\.extracts) }

    var headerLine: String {
        "\(name) — \(TimeFormat.hours(ownHours)) · \(TimeFormat.days(ownHours)) · \(ChatTimeTotals.weeksText(distinctWeeks))"
    }

    /// Rows grouped under their kind's heading, in display order.
    var groups: [(title: String, rows: [TimesheetRow])] {
        let all = rows + unloggedRows
        return TimesheetRowKind.allCases.compactMap { kind in
            let matching = all.filter { $0.kind == kind }
            return matching.isEmpty ? nil : (kind.groupTitle, matching)
        }
    }
}

nonisolated struct TimesheetReport: Equatable, Sendable {
    let nodes: [TimesheetNode]          // roots, by subtree hours desc; the unattributed node last
    let interval: Range<Date>?

    init(nodes: [TimesheetNode] = [], interval: Range<Date>? = nil) {
        self.nodes = nodes
        self.interval = interval
    }

    /// The stable id of the synthetic node holding work that belongs to no project.
    static let unattributedID = UUID(uuidString: "00000000-0000-0000-0000-00000000A11C")!

    var isEmpty: Bool { nodes.isEmpty }

    /// Flattened, pre-order.
    var allNodes: [TimesheetNode] { nodes.flatMap(\.selfAndDescendants) }

    /// Hours across every node — the sum the rows account for. The view's headline is the ledger's
    /// `grandTotal`; a difference between the two is over-logging and is reported, not hidden.
    var totalOwnHours: Double { allNodes.reduce(0) { $0 + $1.ownHours } }

    func node(matching projectName: String) -> TimesheetNode? {
        allNodes.first { $0.name.caseInsensitiveCompare(projectName) == .orderedSame }
    }

    /// The deterministic factual block: each project's header line followed by its bullets.
    func render() -> String {
        allNodes.map { node in
            let bullets = (node.rows + node.unloggedRows).map { "• \($0.bulletLabel)" }.joined(separator: "\n")
            return bullets.isEmpty ? node.headerLine : "\(node.headerLine)\n\(bullets)"
        }.joined(separator: "\n\n")
    }

    /// The "what was done" bullets grouped under each project name with no time header — appended under a
    /// time report that already states the hours. Optionally scoped to one project. Excludes the
    /// unattributed node and every mined extract, so Chat's bounded context stays bounded.
    func narrativeBlock(projectName: String? = nil) -> String {
        let scoped: [TimesheetNode]
        if let projectName {
            scoped = node(matching: projectName).map { [$0] } ?? []   // named but unmatched → nothing
        } else {
            scoped = allNodes
        }
        return scoped.filter { !$0.isUnattributed }.compactMap { node -> String? in
            let visible = node.rows + node.unloggedRows
            guard !visible.isEmpty else { return nil }
            let bullets = visible.map { "• \($0.bulletLabel)\(Self.describedDetails($0))" }
                .joined(separator: "\n")
            return "\(node.name):\n\(bullets)"
        }.joined(separator: "\n\n")
    }

    /// A row's DESCRIBED detail lines only. The stacked "Unspecified work" line is internal bookkeeping —
    /// genuinely useful on screen and in the export (it says how much is undescribed), but a model handed it
    /// writes "…including unspecified work", and Chat would repeat the label as if it were content.
    private static func describedDetails(_ row: TimesheetRow) -> String {
        row.details.filter { !$0.isUnspecified }.map { "\n  – \($0.label)" }.joined()
    }

    /// The strict rephrase-only instruction for one node's prose. Covers the node's whole SUBTREE, so a
    /// parent reads as the project-level summary, and includes the mined extracts the Timesheet holds.
    static func phrasingPrompt(node: TimesheetNode) -> String {
        var lines = node.subtreeRows.map { "• \($0.bulletLabel)\(Self.describedDetails($0))" }
        lines += node.subtreeExtracts.map { "• \($0.title): \($0.text)" }
        let block = lines.joined(separator: "\n")
        return """
        Summarise the following list of work on the project "\(node.name)" into a brief paragraph. Use ONLY \
        these items — do not add, infer, embellish, or omit anything. Never state a figure that is not \
        listed. Keep it concise. \(AISummaryStyle.inline)

        \(block)
        """
    }
}
