import Foundation

// Builds a `ProjectActivityReport` from the SwiftData models — per project, the canonical hours (from
// `TimeLedger`) plus the "what was done" narrative (meetings, completed tasks, logged comments, emails).
// Every narrative date is weekend-folded and interval-filtered exactly like the ledger, so the numbers and
// the narrative always agree. Shared by the Timesheet and Chat.
@MainActor
enum ProjectActivityProjection {
    static func report(interval: Range<Date>?, tasks: [Task], emails: [EmailMessage], meetings: [Minutes],
                       focusBlocks: [FocusBlock], calendar: Calendar = .current,
                       maxEmailsPerProject: Int = 6) -> ProjectActivityReport {
        // Hours / distinct weeks per project — straight from the canonical ledger.
        let ledger = TimeLedgerProjection.ledger(focusBlocks: focusBlocks, tasks: tasks, emails: emails,
                                                 meetings: meetings, interval: interval, calendar: calendar)
        var hoursByProject: [String: (hours: Double, weeks: Int)] = [:]
        for p in ledger.perProject { hoursByProject[p.name] = (p.hours, p.distinctWeeks) }

        func fold(_ date: Date) -> Date { ChatWeekendFold.foldWork(date, calendar: calendar) }
        func inWindow(_ date: Date) -> Bool { interval.map { $0.contains(date) } ?? true }
        func trimmed(_ s: String?) -> String? {
            guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
            return s
        }

        var itemsByProject: [String: [ChatActivityItem]] = [:]
        func add(_ project: String, _ item: ChatActivityItem) { itemsByProject[project, default: []].append(item) }

        // Meetings held.
        for m in meetings {
            let date = fold(m.meetingAt)
            guard inWindow(date), !m.projects.isEmpty else { continue }
            let title = m.summary ?? "Meeting"
            let label = m.duration.map { "Meeting: \(title) (\($0.displayString))" } ?? "Meeting: \(title)"
            let ref = ChatSourceReference(id: m.id, kind: .meeting, title: title, detail: nil,
                                          navigationKind: .meeting, navigationID: m.id)
            for n in m.projects.map(\.name) {
                add(n, ChatActivityItem(date: date, label: label, source: ref, projectNames: [n], kind: .meeting))
            }
        }
        // Tasks completed + logged-time comments on tasks.
        for t in tasks {
            let projectName = t.project?.name
            if t.status == .completed, let completedAt = t.completedAt, let name = projectName {
                let date = fold(completedAt)
                if inWindow(date) {
                    let ref = ChatSourceReference(id: t.id, kind: .task, title: t.summary, detail: nil,
                                                  navigationKind: .task, navigationID: t.id)
                    add(name, ChatActivityItem(date: date, label: "Completed: \(t.summary)", source: ref,
                                               projectNames: [name], kind: .completedTask))
                }
            }
            for e in t.timeEntries where e.email == nil {
                guard let comment = trimmed(e.comment), let name = projectName else { continue }
                let date = fold(e.date)
                guard inWindow(date) else { continue }
                let ref = ChatSourceReference(id: t.id, kind: .task, title: t.summary, detail: nil,
                                              navigationKind: .task, navigationID: t.id)
                add(name, ChatActivityItem(date: date, label: "\(comment) (\(e.duration.displayString))",
                                           source: ref, projectNames: [name], kind: .loggedComment))
            }
        }
        // Logged-time comments on standalone email time.
        for email in emails {
            for e in email.timeEntries where e.task == nil {
                guard let comment = trimmed(e.comment) else { continue }
                let date = fold(e.date)
                guard inWindow(date) else { continue }
                for n in email.projects.map(\.name) {
                    add(n, ChatActivityItem(date: date, label: "\(comment) (\(e.duration.displayString))",
                                            projectNames: [n], kind: .loggedComment))
                }
            }
        }
        // Focus-block comments.
        for b in focusBlocks {
            guard let comment = trimmed(b.comment), let day = b.dayRecord?.date,
                  let name = b.project?.name ?? b.task?.project?.name else { continue }
            let date = fold(day)
            guard inWindow(date) else { continue }
            add(name, ChatActivityItem(date: date, label: "\(comment) (\(b.duration.displayString))",
                                       projectNames: [name], kind: .loggedComment))
        }
        // Emails — importance-first, capped per project.
        var emailsByProject: [String: [(rank: Int, date: Date, item: ChatActivityItem)]] = [:]
        for email in emails {
            let date = fold(email.date)
            guard inWindow(date), !email.projects.isEmpty else { continue }
            let subject = trimmed(email.summary) ?? (trimmed(email.subject) ?? "(no subject)")
            let importance = email.importance == .low ? "" : " [\(email.importance.short)]"
            let ref = ChatSourceReference(id: email.id, kind: .email, title: email.subject, detail: nil,
                                          navigationKind: .email, navigationID: email.id)
            for n in email.projects.map(\.name) {
                let item = ChatActivityItem(date: date, label: "Email: \(subject)\(importance)", source: ref,
                                            projectNames: [n], kind: .email)
                emailsByProject[n, default: []].append((email.importance.rank, date, item))
            }
        }
        for (name, list) in emailsByProject {
            let kept = list.sorted { $0.rank != $1.rank ? $0.rank > $1.rank : $0.date > $1.date }
                .prefix(maxEmailsPerProject)
            for e in kept { add(name, e.item) }
        }

        // Sections = projects with hours OR items (never the "(no project)" hours bucket), by hours desc.
        var names = Set(hoursByProject.keys).union(itemsByProject.keys)
        names.remove(TimeLedger.noProject)
        let sections = names.map { name -> ProjectActivitySection in
            let hw = hoursByProject[name] ?? (0, 0)
            let items = (itemsByProject[name] ?? []).sorted { $0.date < $1.date }
            return ProjectActivitySection(projectName: name, hours: hw.hours, distinctWeeks: hw.weeks, items: items)
        }.sorted { $0.hours != $1.hours ? $0.hours > $1.hours : $0.projectName < $1.projectName }
        return ProjectActivityReport(sections: sections, interval: interval)
    }
}
