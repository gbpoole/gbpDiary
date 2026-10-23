import Foundation

// The machine-readable half of the Timesheet export: the SAME report the page renders, as JSON, so an
// external reader (the MCP server, and through it a local model) can answer time questions with the app's
// own figures instead of re-deriving them from raw rows.
//
// This exists because raw SQL over the store cannot reproduce the canonical rules — focus-block net
// (capacity − in-block logged), weekend work folded to Friday, meetings split across blocks by slot
// overlap, source-key de-duplication, conversation-owned email time. Those live in `TimeLedger` /
// `TimeLedgerProjection` / `TimesheetProjection`; this file is how their output leaves the app intact.
//
// Pure and `Codable`: built from an already-computed `TimesheetReport` + `LedgerResult`, never recomputing.

nonisolated struct TimesheetExportSnapshot: Codable, Equatable, Sendable {
    /// Bumped when the shape changes, so a reader can refuse what it doesn't understand.
    let formatVersion: Int
    let generatedAt: Date
    let period: Period
    let totals: Totals
    let projects: [Node]
    /// Present only for a FULL export: the actual text behind the period, for an agent to work from.
    let content: FullContent?

    struct Period: Codable, Equatable, Sendable {
        let label: String        // e.g. "5 Jan 2026 – 9 Jan 2026"
        let start: Date
        /// Exclusive — the period is a half-open whole-day interval.
        let end: Date
    }

    struct Totals: Codable, Equatable, Sendable {
        /// The headline: the ledger's own figure, the same one the diary shows for these days.
        let hours: Double
        let days: Double
        /// Of `hours`: evening in-block + weekend work.
        let overtimeHours: Double
        /// Planned-block capacity + standalone weekday work, per `TimeLedger`.
        let standardHours: Double
        /// `Σ project hours − hours`, positive only when blocks are over-logged. Explained, not hidden.
        let overLoggedHours: Double
        let projectHoursTotal: Double
    }

    /// One project, nested as projects nest. `hours` is this project ALONE; `subtreeHours` includes children.
    struct Node: Codable, Equatable, Sendable {
        let id: UUID
        let name: String
        let hours: Double
        let subtreeHours: Double
        let distinctWeeks: Int
        let isUnattributed: Bool
        /// Model-written prose for this project + period; "" when none has been generated. Never a figure.
        let summary: String
        let rows: [Row]
        let notes: [NoteExtract]
        let children: [Node]
    }

    /// A row that accounts for part of the project's hours (`kind` == task/meeting/conversation), or a
    /// 0-hour presence row (completedNoTime/unfiledConversation).
    struct Row: Codable, Equatable, Sendable {
        let id: UUID
        let kind: String
        let title: String
        let hours: Double
        let date: Date
        let status: String
        let badge: String
        let details: [Detail]
    }

    struct Detail: Codable, Equatable, Sendable {
        let text: String
        let hours: Double
        /// True for the single stacked line covering a task's undescribed time.
        let isUnspecified: Bool
    }

    struct NoteExtract: Codable, Equatable, Sendable {
        let title: String
        let text: String
        let date: Date
    }

    // MARK: full content

    /// The text behind the period. Deliberately a flat, top-level section rather than nested per project:
    /// a meeting or conversation can belong to several projects, and duplicating its minutes under each
    /// would both bloat the file and create two copies to disagree.
    struct FullContent: Codable, Equatable, Sendable {
        /// States what is and is not here — email BODIES are never stored by the app (read transiently
        /// from Mail, summarised on device, discarded), so no export can contain them.
        let notice: String
        let meetings: [MeetingContent]
        let notes: [NoteContent]
        let conversations: [ConversationContent]
    }

    struct MeetingContent: Codable, Equatable, Sendable {
        let id: UUID
        let summary: String
        let meetingAt: Date
        let durationHours: Double
        let projects: [String]
        let attendees: [String]
        /// The complete minutes markdown — uncapped, unlike the report's clipped extract.
        let minutesMarkdown: String
    }

    struct NoteContent: Codable, Equatable, Sendable {
        let id: UUID
        let title: String
        let project: String
        let day: Date?
        let updatedAt: Date
        let markdown: String
    }

    struct ConversationContent: Codable, Equatable, Sendable {
        let id: UUID
        let subject: String
        let projects: [String]
        let otherParty: String
        let importance: String
        let loggedHours: Double
        let messages: [MessageContent]
    }

    struct MessageContent: Codable, Equatable, Sendable {
        let id: UUID
        let subject: String
        let direction: String
        let date: Date
        let from: String
        /// The on-device generated summary. There is no body field, by design.
        let summary: String
    }
}

nonisolated enum TimesheetDataExport {
    static let formatVersion = 1
    /// The stable file an external reader polls. Rewritten by every Timesheet export.
    static let latestFileName = "timesheet-latest.json"

    /// Carried inside every full export, because "full content" invites exactly the wrong assumption.
    static let contentNotice =
        "Full content export. Meeting minutes and note markdown are complete. THIS JSON contains no email "
        + "bodies, and the app never stores one: a body is read transiently from local Mail, summarised on "
        + "device, and discarded. If this export was made with \"Full content with email bodies\", bodies "
        + "were read at export time and written into the _content directory beside this file — that "
        + "directory is sensitive."

    /// `content` is supplied only for a full export (see `TimesheetContentProjection`).
    static func snapshot(report: TimesheetReport, ledger: LedgerResult, interval: Range<Date>,
                         periodLabel: String, prose: [UUID: String] = [:],
                         content: TimesheetExportSnapshot.FullContent? = nil,
                         generatedAt: Date = Date()) -> TimesheetExportSnapshot {
        TimesheetExportSnapshot(
            formatVersion: formatVersion,
            generatedAt: generatedAt,
            period: .init(label: periodLabel, start: interval.lowerBound, end: interval.upperBound),
            totals: .init(hours: ledger.grandTotal,
                          days: ledger.grandTotal / DurationUnit.d.hoursPerUnit,
                          overtimeHours: ledger.overtime,
                          standardHours: ledger.standardTotal,
                          overLoggedHours: max(0, report.totalOwnHours - ledger.grandTotal),
                          projectHoursTotal: report.totalOwnHours),
            projects: report.nodes.map { node(from: $0, prose: prose) },
            content: content
        )
    }

    private static func node(from node: TimesheetNode, prose: [UUID: String]) -> TimesheetExportSnapshot.Node {
        .init(id: node.id, name: node.name, hours: node.ownHours, subtreeHours: node.subtreeHours,
              distinctWeeks: node.distinctWeeks, isUnattributed: node.isUnattributed,
              summary: prose[node.id] ?? "",
              rows: (node.rows + node.unloggedRows).map { row in
                  .init(id: row.id, kind: row.kind.rawValue, title: row.title, hours: row.hours,
                        date: row.date, status: row.status ?? "", badge: row.badge ?? "",
                        details: row.details.map {
                            .init(text: $0.text, hours: $0.hours, isUnspecified: $0.isUnspecified)
                        })
              },
              notes: node.extracts.map { .init(title: $0.title, text: $0.text, date: $0.date) },
              children: node.children.map { self.node(from: $0, prose: prose) })
    }

    /// ISO-8601 dates and stable key order, so the file diffs cleanly and any reader can parse it.
    /// Note the shape is deliberately STABLE: absent strings are "" rather than missing keys, because
    /// Swift's encoder omits nil optionals and a reader indexing a key that vanished simply breaks.
    /// Only date fields may be absent (there is no empty date).
    static func encode(_ snapshot: TimesheetExportSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    static func decode(_ data: Data) throws -> TimesheetExportSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TimesheetExportSnapshot.self, from: data)
    }

    /// Where the stable snapshot lives — beside the attachments store, inside the app container, which is
    /// what makes it readable by the local MCP server.
    static var exportsDirectory: URL {
        let base: URL
        #if os(macOS)
        base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #else
        base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #endif
        let dir = base.appendingPathComponent("Exports")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var latestURL: URL { exportsDirectory.appendingPathComponent(latestFileName) }

    /// Writes the snapshot to `url`. Exports go ONLY where the user chose — nothing is copied into the app
    /// container, so correspondence never accumulates there. An external reader finds the latest export via
    /// `AppSettingsStore.lastTimesheetExportPath`, which the caller records.
    @discardableResult
    static func write(_ snapshot: TimesheetExportSnapshot, to url: URL) throws -> URL {
        try encode(snapshot).write(to: url, options: .atomic)
        return url
    }
}
