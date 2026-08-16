import Foundation

nonisolated struct ChatCorpusLimits: Equatable, Sendable {
    var maximumSourcesPerKind = 10_000
    var maximumCharactersPerSource = 100_000
}

nonisolated struct ChatAttachmentProjectionFailure: Equatable, Sendable {
    let attachmentID: UUID
    let failure: ChatAttachmentExtractionFailure
}

nonisolated struct ChatCorpusBuildResult: Equatable, Sendable {
    let documents: [ChatRetrievalDocument]
    let attachmentFailures: [ChatAttachmentProjectionFailure]
}

nonisolated struct ChatCorpusSnapshot: Equatable, Sendable {
    let documents: [ChatRetrievalDocument]
    let attachments: [ChatAttachmentDescriptor]
    let maximumCharactersPerSource: Int
}

struct ChatCorpusBuilder {
    // v2: chunks carry projectNames + sortDate metadata for query-scoped retrieval.
    // v3: chunks carry importanceWeight (+ an Importance field for M/H emails) — bumped to force a
    // one-time reindex.
    static let projectionVersion = 3

    var limits = ChatCorpusLimits()
    var attachmentExtractor = ChatAttachmentTextExtractor()

    func build(projects: [Project], tasks: [Task], people: [Person], institutions: [Institution],
               meetings: [Minutes], notes: [Note], days: [DayRecord], documents: [Document],
               emails: [EmailMessage], attachments: [Attachment]) -> ChatCorpusBuildResult {
        ChatCorpusProjection.complete(snapshot: snapshot(
            projects: projects, tasks: tasks, people: people, institutions: institutions,
            meetings: meetings, notes: notes, days: days, documents: documents,
            emails: emails, attachments: attachments
        ), extractor: attachmentExtractor)
    }

    func snapshot(projects: [Project], tasks: [Task], people: [Person], institutions: [Institution],
                  meetings: [Minutes], notes: [Note], days: [DayRecord], documents: [Document],
                  emails: [EmailMessage], attachments: [Attachment]) -> ChatCorpusSnapshot {
        var output: [ChatRetrievalDocument] = []

        append(projects, kind: .project, to: &output) { project in
            document(id: project.id, kind: .project, title: project.name, navigation: .project,
                     detail: joined([project.stream, project.isCompleted ? "Completed" : "Active"]),
                     fields: [
                        ("Description", project.projectDescription), ("Stream", project.stream),
                        ("Tags", list(project.tags)), ("Parent", project.parent?.name),
                        ("Subprojects", list(project.subprojects.map(\.name))),
                        ("Institutions", list(project.institutions.map(\.name))),
                        ("Development team", list(Project.teamNames(lead: project.devLead, team: project.devTeam))),
                        ("Science team", list(Project.teamNames(lead: project.sciLead, team: project.sciTeam)))
                     ], projectNames: [project.name], sortDate: project.updatedAt)
        }
        append(tasks, kind: .task, to: &output) { task in
            document(id: task.id, kind: .task, title: task.summary, navigation: .task,
                     detail: joined([task.status.rawValue, task.project?.name]), fields: [
                        ("Notes", task.notes), ("Status", task.status.rawValue),
                        ("Priority", task.priority.displayName), ("Project", task.project?.name),
                        ("Assignee", task.assignee?.name), ("Institution", task.institution?.name),
                        ("Tags", list(task.tags)), ("Due", date(task.dueAt)),
                        ("Scheduled", date(task.scheduledAt)), ("Recurrence", task.recurrenceRule),
                        ("Blocked by", list(task.dependsOn.map(\.summary)))
                     ], projectNames: [task.project?.name].compactMap { $0 }, sortDate: task.createdAt)
        }
        append(people, kind: .person, to: &output) { person in
            document(id: person.id, kind: .person, title: person.name, navigation: .person,
                     detail: person.institution?.name, fields: [
                        ("Emails", list(person.emails)), ("Institution", person.institution?.name),
                        ("Tags", list(person.tags)),
                        ("Development projects", list(person.devProjects.map(\.name))),
                        ("Science projects", list(person.sciProjects.map(\.name)))
                     ], projectNames: (person.devProjects + person.sciProjects).map(\.name))
        }
        append(institutions, kind: .institution, to: &output) { institution in
            document(id: institution.id, kind: .institution, title: institution.name, navigation: .institution,
                     detail: nil, fields: [
                        ("People", list(institution.members.map(\.name))),
                        ("Projects", list(institution.projects.map(\.name)))
                     ], projectNames: institution.projects.map(\.name))
        }
        append(meetings, kind: .meeting, to: &output) { meeting in
            document(id: meeting.id, kind: .meeting, title: meeting.summary ?? "Meeting", navigation: .meeting,
                     detail: date(meeting.meetingAt), fields: [
                        ("Date", date(meeting.meetingAt)), ("Projects", list(meeting.projects.map(\.name))),
                        ("Attendees", list(meeting.attendees.map(\.name))),
                        ("Duration", meeting.duration?.displayString),
                        ("Minutes", meeting.note?.content ?? meeting.minutesContent),
                        ("Action items", list(meeting.newTasks.map(\.summary))),
                        ("Documents", list(meeting.documents.compactMap(\.summary)))
                     ], projectNames: meeting.projects.map(\.name), sortDate: meeting.meetingAt)
        }
        append(notes.filter { $0.minutes == nil }, kind: .note, to: &output) { note in
            let title = nonempty(note.title) ?? note.dayRecord.map { "Diary note \(date($0.date) ?? "")" } ?? "Note"
            return document(id: note.id, kind: .note, title: title, navigation: .note,
                            detail: joined([note.dayRecord.flatMap { date($0.date) }, note.project?.name]), fields: [
                                ("Date", note.dayRecord.flatMap { date($0.date) }),
                                ("Project", note.project?.name), ("Tags", list(note.tags)), ("Content", note.content)
                            ], projectNames: [note.project?.name].compactMap { $0 }, sortDate: note.dayRecord?.date)
        }
        append(days, kind: .day, to: &output) { day in
            document(id: day.id, kind: .day, title: date(day.date) ?? "Diary", navigation: .day,
                     detail: nil, fields: [
                        ("Date", date(day.date)), ("Focus tags", list(day.focusTags)),
                        ("Legacy notes", day.notes), ("Tasks", list(day.tasks.map(\.summary))),
                        ("Notes", list(day.noteItems.compactMap { nonempty($0.title) })),
                        ("Documents", list(day.documents.compactMap(\.summary)))
                     ], sortDate: day.date)
        }
        append(documents, kind: .document, to: &output) { item in
            document(id: item.id, kind: .document, title: item.summary ?? "Document", navigation: .document,
                     detail: list(item.projects.map(\.name)), fields: [
                        ("Description", item.documentDescription), ("Projects", list(item.projects.map(\.name))),
                        ("Meetings", list(item.meetings.compactMap(\.summary))),
                        ("Files", list(item.attachments.map(\.libraryName)))
                     ], projectNames: item.projects.map(\.name), sortDate: item.createdAt)
        }
        append(emails.filter { !$0.dismissed }, kind: .email, to: &output) { email in
            // Importance shown to the model only for Medium/High (Low is neutral); the weight also drives
            // the ranking boost in ChatHybridRanker.
            let importanceField = email.isImportant ? email.importance.displayName : nil
            return document(id: email.id, kind: .email, title: nonempty(email.subject) ?? "Email", navigation: .email,
                     detail: joined([date(email.date), email.person?.name]), fields: [
                        ("Subject", email.subject), ("Stored summary", email.summary),
                        ("Importance", importanceField),
                        ("Date", date(email.date)), ("Person", email.person?.name),
                        ("Projects", list(email.projects.map(\.name)))
                     ], projectNames: email.projects.map(\.name), sortDate: email.date,
                     importanceWeight: email.importance.weight)
        }

        let attachmentDescriptors = capped(attachments, kind: .attachment).map { attachment in
            let navigation = navigation(for: attachment)
            let source = ChatSourceReference(id: attachment.id, kind: .attachment, title: attachment.libraryName,
                                             detail: navigation.detail, navigationKind: navigation.kind,
                                             navigationID: navigation.id, navigationURL: navigation.url)
            return ChatAttachmentDescriptor(
                id: attachment.id, source: source, fileURL: attachment.fileURL,
                fileName: attachment.fileName, attachmentDescription: attachment.attachmentDescription,
                isPDF: attachment.kind == .pdf || attachment.fileURL.pathExtension.lowercased() == "pdf",
                isText: attachment.kind == .text || Self.textExtensions.contains(attachment.fileURL.pathExtension.lowercased())
                    || attachment.mimeType?.lowercased().hasPrefix("text/") == true
                    || ["application/json", "application/yaml", "application/x-yaml"].contains(attachment.mimeType?.lowercased()),
                mimeType: attachment.mimeType
            )
        }
        return ChatCorpusSnapshot(documents: output.sorted(by: Self.documentOrder),
                                  attachments: attachmentDescriptors,
                                  maximumCharactersPerSource: limits.maximumCharactersPerSource)
    }

    private func append<T>(_ values: [T], kind: ChatSourceKind, to output: inout [ChatRetrievalDocument],
                           transform: (T) -> ChatRetrievalDocument) where T: Identifiable, T.ID == UUID {
        output.append(contentsOf: capped(values, kind: kind).map(transform))
    }

    private func capped<T>(_ values: [T], kind: ChatSourceKind) -> [T] where T: Identifiable, T.ID == UUID {
        Array(values.sorted { $0.id.uuidString < $1.id.uuidString }.prefix(max(0, limits.maximumSourcesPerKind)))
    }

    private func document(id: UUID, kind: ChatSourceKind, title: String, navigation: ChatNavigationKind,
                          navigationID: UUID? = nil, detail: String?, fields: [(String, String?)],
                          projectNames: [String] = [], sortDate: Date? = nil,
                          importanceWeight: Double = 0) -> ChatRetrievalDocument {
        let metadata = fields.compactMap { label, value -> String? in
            guard let value = nonempty(value) else { return nil }
            return "\(label): \(value)"
        }
        let content = (["Title: \(nonempty(title) ?? kind.displayName)"] + metadata).joined(separator: "\n")
        let bounded = String(content.prefix(max(0, limits.maximumCharactersPerSource)))
        let source = ChatSourceReference(id: id, kind: kind, title: title, detail: detail,
                                         navigationKind: navigation, navigationID: navigationID)
        let normalizedProjects = projectNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        return ChatRetrievalDocument(source: source, markdown: bounded,
                                     projectNames: normalizedProjects, sortDate: sortDate,
                                     importanceWeight: importanceWeight)
    }

    private func navigation(for attachment: Attachment) -> (kind: ChatNavigationKind, id: UUID, detail: String?, url: URL?) {
        if let document = attachment.document { return (.document, document.id, document.summary, nil) }
        if let note = attachment.note {
            if let minutes = note.minutes { return (.meeting, minutes.id, minutes.summary, nil) }
            if let day = note.dayRecord { return (.day, day.id, date(day.date), nil) }
            return (.note, note.id, nonempty(note.title), nil)
        }
        return (.attachment, attachment.id, nil, attachment.fileURL)
    }

    private func list(_ values: [String]) -> String? {
        let result = values.compactMap(nonempty).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return result.isEmpty ? nil : result.joined(separator: ", ")
    }

    private func joined(_ values: [String?]) -> String? {
        let result = values.compactMap(nonempty)
        return result.isEmpty ? nil : result.joined(separator: " · ")
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private func date(_ value: Date?) -> String? {
        guard let value else { return nil }
        return Self.dateFormatter.string(from: value)
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    nonisolated private static func documentOrder(_ lhs: ChatRetrievalDocument, _ rhs: ChatRetrievalDocument) -> Bool {
        if lhs.source.kind.rawValue != rhs.source.kind.rawValue { return lhs.source.kind.rawValue < rhs.source.kind.rawValue }
        return lhs.id < rhs.id
    }

    private static let textExtensions: Set<String> = ["txt", "text", "md", "markdown", "csv", "json", "yaml", "yml"]
}

nonisolated enum ChatCorpusProjection {
    nonisolated static func complete(snapshot: ChatCorpusSnapshot,
                                     extractor: ChatAttachmentTextExtractor = ChatAttachmentTextExtractor()) -> ChatCorpusBuildResult {
        var documents = snapshot.documents
        var failures: [ChatAttachmentProjectionFailure] = []
        for attachment in snapshot.attachments {
            let extraction = extractor.extract(attachment)
            guard let text = extraction.text else {
                if let failure = extraction.failure {
                    failures.append(ChatAttachmentProjectionFailure(attachmentID: attachment.id, failure: failure))
                }
                continue
            }
            let fields = [
                attachment.attachmentDescription.map { "Description: \($0)" },
                "File: \(attachment.fileName)",
                "Attachment text: \(text)"
            ].compactMap { $0 }
            let content = (["Title: \(attachment.source.title)"] + fields).joined(separator: "\n")
            documents.append(ChatRetrievalDocument(
                source: attachment.source,
                markdown: String(content.prefix(max(0, snapshot.maximumCharactersPerSource)))
            ))
        }
        return ChatCorpusBuildResult(
            documents: documents.sorted { $0.id < $1.id },
            attachmentFailures: failures.sorted { $0.attachmentID.uuidString < $1.attachmentID.uuidString }
        )
    }
}
