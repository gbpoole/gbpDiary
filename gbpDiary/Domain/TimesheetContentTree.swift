import Foundation

// The full-content export as a tree of markdown files, one directory per project — the shape an agent can
// read with ordinary file tools, rather than one nested JSON document it has to parse.
//
// Pure by design: `compose` returns (relative path → contents) so the entire layout is unit-tested without
// touching the filesystem. `TimesheetContentTreeWriter` does the only I/O.

/// One file in the exported tree. `path` is always relative, with no leading slash and no `..`.
nonisolated struct TimesheetExportFile: Equatable, Sendable {
    let path: String
    let contents: String
}

/// What happened when the export tried to obtain one message's body. Recorded for EVERY message, so a
/// partial result is readable rather than ambiguous: an absent body always states its reason.
nonisolated enum TimesheetEmailBody: Equatable, Sendable {
    case fetched(String)
    case truncated(String, originalCount: Int)
    case failed(String)             // MailScriptError.userMessage
    case skippedNotRelevant         // not filed, not accepted, no logged time
    case skippedNoMessageID         // no Mail id stored — not worth a round trip
    case skippedStopped             // the user stopped the run
    case notRequested               // bodies weren't asked for
}

nonisolated enum TimesheetContentTree {
    static let unattributedDirectory = "Unattributed"
    static let maxBodyCharacters = 20_000

    static let bodyWarning =
        "> **This directory can contain full email bodies** read from local Mail at export time. "
        + "They are not stored in the app — only here, in the location you chose. Treat it accordingly."

    // MARK: compose

    /// The whole tree. `bodies` is keyed by `MessageContent.id`; a missing key means the body was never
    /// requested. `trimQuotedHistory` drops the quoted reply chain that every reply repeats — each earlier
    /// message is already its own file, so this removes duplication, not information.
    static func compose(content: TimesheetExportSnapshot.FullContent,
                        periodLabel: String,
                        bodies: [UUID: TimesheetEmailBody] = [:],
                        generatedAt: Date = Date(),
                        trimQuotedHistory: Bool = true,
                        calendar: Calendar = .current) -> [TimesheetExportFile] {
        var files: [TimesheetExportFile] = []
        var allocator = NameAllocator()

        for meeting in content.meetings {
            let body = meetingMarkdown(meeting, calendar: calendar)
            let name = allocator.name(date: meeting.meetingAt, title: meeting.summary,
                                      fallback: "Meeting", calendar: calendar)
            for directory in directories(for: meeting.projects) {
                files.append(.init(path: "\(directory)/meetings/\(name)", contents: body))
            }
        }

        for note in content.notes {
            let body = noteMarkdown(note, calendar: calendar)
            let name = allocator.name(date: note.day ?? note.updatedAt, title: note.title,
                                      fallback: "Note", calendar: calendar)
            for directory in directories(for: note.project.isEmpty ? [] : [note.project]) {
                files.append(.init(path: "\(directory)/notes/\(name)", contents: body))
            }
        }

        for conversation in content.conversations {
            let body = conversationMarkdown(conversation, bodies: bodies,
                                            trimQuotedHistory: trimQuotedHistory, calendar: calendar)
            let name = allocator.name(date: conversation.messages.last?.date ?? generatedAt,
                                      title: conversation.subject, fallback: "Email", calendar: calendar)
            for directory in directories(for: conversation.projects) {
                files.append(.init(path: "\(directory)/email/\(name)", contents: body))
            }
        }

        files.insert(.init(path: "README.md",
                           contents: indexMarkdown(periodLabel: periodLabel, generatedAt: generatedAt,
                                                   files: files, content: content, bodies: bodies)),
                     at: 0)
        return files
    }

    /// A project name as a directory name. Reuses the existing sanitiser, which keeps only alphanumerics
    /// plus space/`-`/`_` — so `/`, `:` and `..` cannot survive and nothing can escape the export root.
    static func directoryName(project: String) -> String {
        MinutesExport.exportBaseName(summary: project, fallback: unattributedDirectory)
    }

    private static func directories(for projects: [String]) -> [String] {
        let named = projects.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !named.isEmpty else { return [unattributedDirectory] }
        // An item on several projects is written under each: an agent reading one project's folder then
        // sees everything that touched it, with no link to follow. Within a single export the copies are
        // generated together from one source, so they cannot disagree.
        var seen = Set<String>()
        return named.map(directoryName(project:)).filter { seen.insert($0).inserted }
    }

    // MARK: per-item markdown

    static func meetingMarkdown(_ meeting: TimesheetExportSnapshot.MeetingContent,
                                calendar: Calendar = .current) -> String {
        var out = ["# \(meeting.summary.isEmpty ? "Meeting" : meeting.summary)", ""]
        out.append("*\(dateTime(meeting.meetingAt, calendar: calendar))*"
                   + (meeting.durationHours > 0 ? " · \(TimeFormat.hours(meeting.durationHours))" : ""))
        if !meeting.projects.isEmpty { out.append("**Projects:** \(meeting.projects.joined(separator: ", "))") }
        if !meeting.attendees.isEmpty { out.append("**Attendees:** \(meeting.attendees.joined(separator: ", "))") }
        out.append("")
        out.append(meeting.minutesMarkdown.isEmpty ? "_No minutes recorded._" : meeting.minutesMarkdown)
        return out.joined(separator: "\n") + "\n"
    }

    static func noteMarkdown(_ note: TimesheetExportSnapshot.NoteContent,
                             calendar: Calendar = .current) -> String {
        var out = ["# \(note.title.isEmpty ? "Note" : note.title)", ""]
        out.append("*Updated \(dateTime(note.updatedAt, calendar: calendar))*")
        if !note.project.isEmpty { out.append("**Project:** \(note.project)") }
        if let day = note.day { out.append("**Diary day:** \(dateOnly(day, calendar: calendar))") }
        out.append("")
        out.append(note.markdown)
        return out.joined(separator: "\n") + "\n"
    }

    static func conversationMarkdown(_ conversation: TimesheetExportSnapshot.ConversationContent,
                                     bodies: [UUID: TimesheetEmailBody] = [:],
                                     trimQuotedHistory: Bool = true,
                                     calendar: Calendar = .current) -> String {
        var out = ["# \(conversation.subject.isEmpty ? "Email" : conversation.subject)", ""]
        if !conversation.projects.isEmpty {
            out.append("**Projects:** \(conversation.projects.joined(separator: ", "))")
        }
        if !conversation.otherParty.isEmpty { out.append("**With:** \(conversation.otherParty)") }
        out.append("**Importance:** \(conversation.importance)")
        if conversation.loggedHours > 0 {
            out.append("**Logged:** \(TimeFormat.hours(conversation.loggedHours))")
        }

        for message in conversation.messages {
            out.append("")
            out.append("## \(dateTime(message.date, calendar: calendar)) — \(message.direction) — \(message.from)")
            out.append("")
            out.append(message.summary.isEmpty ? "_No summary._" : "_Summary:_ \(message.summary)")
            out.append("")
            out.append(contentsOf: bodySection(bodies[message.id] ?? .notRequested,
                                               trimQuotedHistory: trimQuotedHistory))
        }
        return out.joined(separator: "\n") + "\n"
    }

    private static func bodySection(_ body: TimesheetEmailBody, trimQuotedHistory: Bool) -> [String] {
        switch body {
        case .fetched(let text), .truncated(let text, _):
            let shown = trimQuotedHistory ? EmailQuotedHistory.newestMessage(text) : text
            guard !shown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return ["_Body was empty._"]
            }
            var lines = ["**Body**", ""]
            if case .truncated(_, let original) = body {
                lines.append("_Truncated to \(maxBodyCharacters) of \(original) characters._")
                lines.append("")
            }
            if trimQuotedHistory, shown.count < text.count {
                lines.append("_Quoted reply history trimmed; earlier messages appear above._")
                lines.append("")
            }
            lines.append(fencedBlock(shown))
            return lines
        case .failed(let reason):        return ["_Body unavailable: \(reason)_"]
        case .skippedNotRelevant:        return ["_Body not fetched: not filed to a project, not accepted, no logged time._"]
        case .skippedNoMessageID:        return ["_Body not fetched: no Mail id stored for this message._"]
        case .skippedStopped:            return ["_Body not fetched: the export was stopped._"]
        case .notRequested:              return ["_Body not requested._"]
        }
    }

    /// Fences with more backticks than any run inside the text, so a body containing code can't break out.
    static func fencedBlock(_ text: String) -> String {
        var longest = 0, current = 0
        for character in text {
            current = character == "`" ? current + 1 : 0
            longest = max(longest, current)
        }
        let fence = String(repeating: "`", count: max(3, longest + 1))
        return "\(fence)text\n\(text)\n\(fence)"
    }

    /// Caps a body before it reaches the tree.
    static func clamp(_ body: String) -> TimesheetEmailBody {
        body.count > maxBodyCharacters
            ? .truncated(String(body.prefix(maxBodyCharacters)), originalCount: body.count)
            : .fetched(body)
    }

    // MARK: index

    static func indexMarkdown(periodLabel: String, generatedAt: Date, files: [TimesheetExportFile],
                              content: TimesheetExportSnapshot.FullContent,
                              bodies: [UUID: TimesheetEmailBody]) -> String {
        var out = ["# Content — \(periodLabel)", "",
                   "*Exported \(dateTime(generatedAt, calendar: .current))*", ""]

        let counts = rollUp(content: content, bodies: bodies)
        if counts.requested > 0 || counts.failed > 0 {
            out.append(bodyWarning)
            out.append("")
            out.append("**Email bodies:** \(counts.fetched) fetched, \(counts.failed) unavailable, "
                       + "\(counts.skipped) not fetched.")
            out.append("")
        } else {
            out.append("_No email bodies were requested for this export — messages carry their subject and "
                       + "the on-device summary only._")
            out.append("")
        }

        if files.isEmpty {
            out.append("_No meetings, notes or correspondence in this period._")
            return out.joined(separator: "\n") + "\n"
        }

        var byDirectory: [String: [String]] = [:]
        for file in files where file.path != "README.md" {
            let parts = file.path.split(separator: "/", maxSplits: 1)
            guard parts.count == 2 else { continue }
            byDirectory[String(parts[0]), default: []].append(file.path)
        }
        for directory in byDirectory.keys.sorted() {
            out.append("## \(directory)")
            out.append("")
            for path in (byDirectory[directory] ?? []).sorted() {
                let name = path.split(separator: "/").last.map(String.init) ?? path
                out.append("- [\(name)](\(path.replacingOccurrences(of: " ", with: "%20")))")
            }
            out.append("")
        }
        return out.joined(separator: "\n") + "\n"
    }

    private static func rollUp(content: TimesheetExportSnapshot.FullContent,
                               bodies: [UUID: TimesheetEmailBody])
    -> (requested: Int, fetched: Int, failed: Int, skipped: Int) {
        var fetched = 0, failed = 0, skipped = 0
        for conversation in content.conversations {
            for message in conversation.messages {
                switch bodies[message.id] ?? .notRequested {
                case .fetched, .truncated: fetched += 1
                case .failed: failed += 1
                case .skippedNotRelevant, .skippedNoMessageID, .skippedStopped: skipped += 1
                case .notRequested: break
                }
            }
        }
        return (fetched + failed + skipped, fetched, failed, skipped)
    }

    // MARK: naming

    /// Allocates `yyyy-MM-dd Title.md` names, suffixing duplicates within the same directory-kind so two
    /// meetings with one title never overwrite each other. Deterministic: the projection's ordering is.
    private struct NameAllocator {
        private var used: Set<String> = []

        mutating func name(date: Date, title: String, fallback: String, calendar: Calendar) -> String {
            let base = "\(dateOnly(date, calendar: calendar)) "
                + MinutesExport.exportBaseName(summary: title, fallback: fallback)
            var candidate = base
            var suffix = 2
            while !used.insert(candidate).inserted {
                candidate = "\(base) \(suffix)"
                suffix += 1
            }
            return candidate + ".md"
        }
    }

    private static func dateOnly(_ date: Date, calendar: Calendar) -> String {
        formatter("yyyy-MM-dd", calendar: calendar).string(from: date)
    }
    private static func dateTime(_ date: Date, calendar: Calendar) -> String {
        formatter("d MMM yyyy HH:mm", calendar: calendar).string(from: date)
    }
    private static func formatter(_ format: String, calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = format
        return f
    }
}
