import Foundation

// Builds a `TimesheetReport` from the SwiftData models.
//
// The hours are NOT recomputed here. `TimeLedgerProjection` → `TimeLedger` remains the single source of
// truth; this walks the ledger's OWN filtered, de-duplicated, weekend-folded inputs (`TimeLedger.filtered`)
// and turns each one into the row that accounts for it, using the provenance the ledger carries
// (`LedgerOrigin`). That is what makes `rowsHours == ownHours` hold by construction rather than by two
// implementations happening to agree.
//
// Beyond the hours it adds what the hours alone can't say: tasks completed with nothing logged, email
// conversations, mined note prose (`extracts`, explicitly-linked only), and an unattributed node so time
// that belongs to no project is reported instead of silently deleted.
@MainActor
enum TimesheetProjection {

    static func report(interval: Range<Date>?,
                       tasks: [Task],
                       conversations: [EmailConversation],
                       meetings: [Minutes],
                       focusBlocks: [FocusBlock],
                       notes: [Note] = [],
                       projects: [Project] = [],
                       calendar: Calendar = .current,
                       maxExtractCharacters: Int = 360) -> TimesheetReport {

        // 1. The canonical hours, and the exact inputs they were computed from.
        let (allBlocks, allActivities) = TimeLedgerProjection.project(
            focusBlocks: focusBlocks, tasks: tasks, conversations: conversations,
            meetings: meetings, calendar: calendar)
        let ledger = TimeLedger.compute(blocks: allBlocks, activities: allActivities,
                                        interval: interval, calendar: calendar)
        let counted = TimeLedger.filtered(blocks: allBlocks, activities: allActivities, interval: interval)

        // 2. Model lookups for naming the work.
        let tasksByID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let meetingsByID = Dictionary(meetings.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let convosByID = Dictionary(conversations.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let blocksByID = Dictionary(focusBlocks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var entriesByID: [UUID: TaskTimeEntry] = [:]
        for t in tasks { for e in t.timeEntries { entriesByID[e.id] = e } }
        for c in conversations { for e in c.timeEntries { entriesByID[e.id] = e } }

        func inWindow(_ date: Date) -> Bool { interval.map { $0.contains(date) } ?? true }
        func trimmed(_ s: String?) -> String? {
            guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
            return s
        }

        var builder = RowBuilder()

        // 3. Every counted ACTIVITY becomes (part of) a row under each project it is attributed to.
        for activity in counted.activities {
            let projects = activity.projects.isEmpty ? [TimeLedger.unattributed] : activity.projects
            for project in projects {
                switch activity.origin?.kind {
                case .taskEntry, .legacyTask:
                    let taskID = activity.origin?.ownerID ?? activity.origin?.modelID
                    guard let taskID, let task = tasksByID[taskID] else {
                        builder.addOther(project: project, hours: activity.hours, date: activity.date)
                        continue
                    }
                    let comment = activity.origin?.kind == .taskEntry
                        ? trimmed(entriesByID[activity.origin?.modelID ?? taskID]?.comment)
                        : nil
                    builder.add(project: project, kind: .task, id: task.id, title: task.summary,
                                hours: activity.hours, date: activity.date,
                                status: Self.completionStatus(task, calendar: calendar),
                                source: Self.taskSource(task), comment: comment)
                case .meeting:
                    guard let id = activity.origin?.modelID, let meeting = meetingsByID[id] else {
                        builder.addOther(project: project, hours: activity.hours, date: activity.date)
                        continue
                    }
                    builder.add(project: project, kind: .meeting, id: meeting.id,
                                title: meeting.summary ?? "Meeting", hours: activity.hours,
                                date: activity.date, source: Self.meetingSource(meeting), comment: nil)
                case .conversationEntry:
                    guard let convoID = activity.origin?.ownerID, let convo = convosByID[convoID] else {
                        builder.addOther(project: project, hours: activity.hours, date: activity.date)
                        continue
                    }
                    let comment = trimmed(entriesByID[activity.origin?.modelID ?? convoID]?.comment)
                    builder.add(project: project, kind: .conversation, id: convo.id,
                                title: convo.displaySubject, hours: activity.hours, date: activity.date,
                                badge: Self.conversationBadge(convo, interval: interval, calendar: calendar),
                                source: Self.conversationSource(convo), comment: comment)
                case nil:
                    builder.addOther(project: project, hours: activity.hours, date: activity.date)
                }
            }
        }

        // 4. Every standard block's NET is real work on its backing task — a row, like a logged entry.
        for block in counted.blocks where !block.isOvertime {
            let net = ledger.blockNet[block.id] ?? 0
            guard net > 0, let model = blocksByID[block.id] else { continue }
            let project = block.project ?? TimeLedger.unattributed
            let comment = trimmed(model.comment)
            if let task = model.task {
                builder.add(project: project, kind: .task, id: task.id, title: task.summary,
                            hours: net, date: block.date,
                            status: Self.completionStatus(task, calendar: calendar),
                            source: Self.taskSource(task), comment: comment)
            } else {
                // A block with no backing task (an evening container is excluded above): name it by its label.
                builder.add(project: project, kind: .task, id: model.id, title: model.displayLabel,
                            hours: net, date: block.date, source: nil, comment: comment)
            }
        }

        // 5. Completed in the range with nothing logged against it — named, contributing 0h.
        for task in tasks where task.status == .completed {
            guard let completedAt = task.completedAt else { continue }
            let date = ChatWeekendFold.foldWork(completedAt, calendar: calendar)
            guard inWindow(date) else { continue }
            let project = TimeLedgerProjection.ledgerProject(task.project) ?? TimeLedger.unattributed
            guard !builder.hasRow(project: project, kind: .task, id: task.id) else { continue }
            builder.addPresence(project: project, kind: .completedNoTime, id: task.id, title: task.summary,
                                date: date, status: Self.completionStatus(task, calendar: calendar),
                                source: Self.taskSource(task))
        }

        // 6. Correspondence that was never filed to a project — reported so it can be fixed, not hidden.
        for convo in conversations where convo.projects.isEmpty && convo.triageState != .dismissed {
            let dates = convo.messages.map { Self.foldedDate(of: $0, calendar: calendar) }.filter(inWindow)
            guard let latest = dates.max() else { continue }
            builder.addPresence(project: TimeLedger.unattributed, kind: .unfiledConversation, id: convo.id,
                                title: convo.displaySubject, date: latest,
                                badge: Self.conversationBadge(convo, interval: interval, calendar: calendar),
                                source: Self.conversationSource(convo))
        }

        // 7. Mined prose — EXPLICIT links only (a meeting's own projects, a note's own project).
        var extracts: [String: [TimesheetExtract]] = [:]
        for meeting in meetings where !meeting.projects.isEmpty {
            let date = ChatWeekendFold.foldWork(meeting.meetingAt, calendar: calendar)
            guard inWindow(date),
                  let body = Self.extractText(meeting.note?.content ?? meeting.minutesContent,
                                              limit: maxExtractCharacters) else { continue }
            let title = "Minutes: \(meeting.summary ?? "Meeting")"
            for project in meeting.projects {
                let key = project.id.uuidString
                extracts[key, default: []].append(
                    TimesheetExtract(id: meeting.id, title: title, text: body, date: date,
                                     source: Self.meetingSource(meeting)))
            }
        }
        for note in notes {
            guard let project = note.project, note.minutes == nil else { continue }
            let date = ChatWeekendFold.foldWork(note.updatedAt, calendar: calendar)
            guard inWindow(date),
                  let body = Self.extractText(note.content, limit: maxExtractCharacters) else { continue }
            let title = trimmed(note.title).map { "Note: \($0)" } ?? "Note"
            extracts[project.id.uuidString, default: []].append(
                TimesheetExtract(id: note.id, title: title, text: body, date: date,
                                 source: Self.noteSource(note)))
        }

        // 8. Assemble the nested nodes.
        return assemble(ledger: ledger, builder: builder, extracts: extracts,
                        projects: projects, interval: interval)
    }

    // MARK: node assembly

    private static func assemble(ledger: LedgerResult, builder: RowBuilder,
                                 extracts: [String: [TimesheetExtract]],
                                 projects: [Project],
                                 interval: Range<Date>?) -> TimesheetReport {
        var hoursByKey: [String: (hours: Double, weeks: Int)] = [:]
        var namesByKey: [String: String] = [:]
        for p in ledger.perProject {
            hoursByKey[p.key] = (p.hours, p.distinctWeeks)
            namesByKey[p.key] = p.name
        }
        let allProjectsByKey = Dictionary(projects.map { ($0.id.uuidString, $0) },
                                          uniquingKeysWith: { a, _ in a })

        // Every key that has hours, rows, or mined prose.
        var keys = Set(hoursByKey.keys).union(builder.keys).union(extracts.keys)
        let unattributedKey = TimeLedger.noProject
        let hasUnattributed = keys.remove(unattributedKey) != nil

        // Resolve each key to its project model (for the name + parent chain), pulling in ancestors so the
        // nesting is coherent even when a parent logged nothing itself.
        var projectsByKey: [String: Project] = [:]
        for key in keys { if let p = allProjectsByKey[key] { projectsByKey[key] = p } }
        var pending = Array(projectsByKey.values)
        while let project = pending.popLast() {
            guard let parent = project.parent else { continue }
            let parentKey = parent.id.uuidString
            if projectsByKey[parentKey] == nil {
                projectsByKey[parentKey] = parent
                keys.insert(parentKey)
                pending.append(parent)
            }
        }

        func node(for key: String) -> TimesheetNode {
            let project = projectsByKey[key]
            let hw = hoursByKey[key] ?? (0, 0)
            let children = projectsByKey.values
                .filter { $0.parent?.id.uuidString == key }
                .map { node(for: $0.id.uuidString) }
                .sorted(by: ordered)
            return TimesheetNode(id: project?.id ?? TimesheetReport.unattributedID,
                                 key: key,
                                 name: project?.name ?? namesByKey[key] ?? builder.name(forKey: key) ?? key,
                                 ownHours: hw.hours, distinctWeeks: hw.weeks,
                                 rows: builder.rows(forKey: key),
                                 unloggedRows: builder.presenceRows(forKey: key),
                                 extracts: (extracts[key] ?? []).sorted { $0.date < $1.date },
                                 children: children)
        }

        var roots = projectsByKey
            .filter { key, project in
                let parentKey = project.parent?.id.uuidString
                return parentKey == nil || projectsByKey[parentKey!] == nil
            }
            .map { node(for: $0.key) }
            .sorted(by: ordered)
        // A key with no resolvable project model (a stale name-keyed row) still gets a root node.
        for key in keys where projectsByKey[key] == nil {
            roots.append(node(for: key))
        }
        roots.sort(by: ordered)

        if hasUnattributed {
            let hw = hoursByKey[unattributedKey] ?? (0, 0)
            let unattributed = TimesheetNode(id: TimesheetReport.unattributedID, key: unattributedKey,
                                             name: "Unattributed", ownHours: hw.hours,
                                             distinctWeeks: hw.weeks,
                                             rows: builder.rows(forKey: unattributedKey),
                                             unloggedRows: builder.presenceRows(forKey: unattributedKey),
                                             extracts: [], children: [], isUnattributed: true)
            if unattributed.ownHours > 0 || unattributed.hasContent { roots.append(unattributed) }   // always last
        }
        return TimesheetReport(nodes: roots, interval: interval)
    }

    /// Biggest subtree first, then by name — so a parent whose work all sits in subprojects still ranks.
    private static func ordered(_ a: TimesheetNode, _ b: TimesheetNode) -> Bool {
        a.subtreeHours != b.subtreeHours ? a.subtreeHours > b.subtreeHours : a.name < b.name
    }

    // MARK: labels + sources

    private static func completionStatus(_ task: Task, calendar: Calendar) -> String? {
        guard task.status == .completed, let date = task.completedAt else { return nil }
        return "✓ \(Self.dayFormatter.string(from: date))"
    }

    private static func conversationBadge(_ convo: EmailConversation, interval: Range<Date>?,
                                          calendar: Calendar) -> String? {
        let inRange = convo.messages.filter { message in
            interval.map { $0.contains(Self.foldedDate(of: message, calendar: calendar)) } ?? true
        }
        let sent = inRange.filter { $0.direction == .sent }.count
        let received = inRange.count - sent
        guard sent + received > 0 else { return nil }
        let importance = convo.importance == .low ? "" : " [\(convo.importance.short)]"
        return "\(sent) sent · \(received) recv\(importance)"
    }

    /// A message's reporting date: sent mail is work (weekend → Friday), received mail is inbound
    /// (weekend → Monday) — the same split the rest of the app uses.
    private static func foldedDate(of message: EmailMessage, calendar: Calendar) -> Date {
        message.direction == .sent
            ? ChatWeekendFold.foldWork(message.date, calendar: calendar)
            : ChatWeekendFold.fold(message.date, kind: .email, calendar: calendar)
    }

    private static func taskSource(_ task: Task) -> ChatSourceReference {
        ChatSourceReference(id: task.id, kind: .task, title: task.summary, detail: nil,
                            navigationKind: .task, navigationID: task.id)
    }
    private static func meetingSource(_ meeting: Minutes) -> ChatSourceReference {
        ChatSourceReference(id: meeting.id, kind: .meeting, title: meeting.summary ?? "Meeting", detail: nil,
                            navigationKind: .meeting, navigationID: meeting.id)
    }
    private static func conversationSource(_ convo: EmailConversation) -> ChatSourceReference? {
        guard let latest = convo.latest else { return nil }
        return ChatSourceReference(id: latest.id, kind: .email, title: convo.subject, detail: nil,
                                   navigationKind: .email, navigationID: latest.id)
    }
    private static func noteSource(_ note: Note) -> ChatSourceReference {
        ChatSourceReference(id: note.id, kind: .note, title: note.title, detail: nil,
                            navigationKind: .note, navigationID: note.id)
    }

    /// Bounded, markdown-stripped prose for an extract — nil when there is nothing readable.
    private static func extractText(_ markdown: String?, limit: Int) -> String? {
        guard let markdown, !markdown.isEmpty else { return nil }
        let flat = ChatMarkdownNormalizer.normalize(markdown)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = flat.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMM"
        return f
    }()

    // MARK: row accumulation

    /// Accumulates hours and detail lines per (project, row), so a task worked across a fortnight is ONE
    /// row, and all of its undescribed time collapses into ONE "Unspecified work" line.
    private struct RowBuilder {
        private struct Key: Hashable { let projectKey: String; let kind: TimesheetRowKind; let id: UUID }
        private struct Accumulator {
            var title: String
            var hours: Double
            var date: Date
            var status: String?
            var badge: String?
            var described: [(text: String, hours: Double)]
            var unspecified: Double
            var source: ChatSourceReference?
        }

        private var accumulators: [Key: Accumulator] = [:]
        private var order: [Key] = []
        private var presence: [Key: TimesheetRow] = [:]
        private var presenceOrder: [Key] = []
        private var names: [String: String] = [:]

        var keys: Set<String> {
            Set(order.map(\.projectKey)).union(presenceOrder.map(\.projectKey))
        }

        mutating func note(project: LedgerProject) {
            names[project.key] = project.name
        }

        mutating func add(project: LedgerProject, kind: TimesheetRowKind, id: UUID, title: String,
                          hours: Double, date: Date, status: String? = nil, badge: String? = nil,
                          source: ChatSourceReference?, comment: String?) {
            note(project: project)
            let key = Key(projectKey: project.key, kind: kind, id: id)
            if accumulators[key] == nil {
                order.append(key)
                accumulators[key] = Accumulator(title: title, hours: 0, date: date, status: status,
                                                badge: badge, described: [], unspecified: 0, source: source)
            }
            guard var acc = accumulators[key] else { return }
            acc.hours += hours
            acc.date = max(acc.date, date)
            if let status { acc.status = status }
            if let badge { acc.badge = badge }
            if let comment {
                acc.described.append((comment, hours))
            } else if hours > 0 {
                acc.unspecified += hours
            }
            accumulators[key] = acc
        }

        /// Hours the ledger counted whose provenance we could not resolve: still reported, never dropped.
        mutating func addOther(project: LedgerProject, hours: Double, date: Date) {
            add(project: project, kind: .task, id: TimesheetReport.unattributedID,
                title: "Other logged time", hours: hours, date: date, source: nil, comment: nil)
        }

        mutating func addPresence(project: LedgerProject, kind: TimesheetRowKind, id: UUID, title: String,
                                  date: Date, status: String? = nil, badge: String? = nil,
                                  source: ChatSourceReference?) {
            note(project: project)
            let key = Key(projectKey: project.key, kind: kind, id: id)
            guard presence[key] == nil else { return }
            presenceOrder.append(key)
            presence[key] = TimesheetRow(id: id, kind: kind, title: title, hours: 0, date: date,
                                         status: status, badge: badge, source: source)
        }

        func hasRow(project: LedgerProject, kind: TimesheetRowKind, id: UUID) -> Bool {
            accumulators[Key(projectKey: project.key, kind: kind, id: id)] != nil
        }

        func name(forKey key: String) -> String? { names[key] }

        func rows(forKey key: String) -> [TimesheetRow] {
            order.filter { $0.projectKey == key }.compactMap { k -> TimesheetRow? in
                guard let a = accumulators[k] else { return nil }
                var details = a.described.map { TimesheetDetail(text: $0.text, hours: $0.hours) }
                // Only a TASK's undescribed time needs naming. A meeting or a conversation is already
                // described by its own title, so "Unspecified work" there is pure noise.
                if a.unspecified > 0, k.kind == .task {
                    details.append(TimesheetDetail(text: "Unspecified work", hours: a.unspecified,
                                                   isUnspecified: true))
                }
                return TimesheetRow(id: k.id, kind: k.kind, title: a.title, hours: a.hours, date: a.date,
                                    status: a.status, badge: a.badge, details: details, source: a.source)
            }
            .sorted { $0.hours != $1.hours ? $0.hours > $1.hours : $0.date > $1.date }
        }

        func presenceRows(forKey key: String) -> [TimesheetRow] {
            presenceOrder.filter { $0.projectKey == key }.compactMap { presence[$0] }
                .sorted { $0.date > $1.date }
        }
    }
}
