import CryptoKit
import Foundation
import SwiftData

private protocol StableModelIdentified {
    var id: UUID { get }
}

extension Institution: StableModelIdentified {}
extension Person: StableModelIdentified {}
extension Project: StableModelIdentified {}
extension Minutes: StableModelIdentified {}
extension Document: StableModelIdentified {}
extension Note: StableModelIdentified {}
extension DayRecord: StableModelIdentified {}
extension Task: StableModelIdentified {}
extension DayEntry: StableModelIdentified {}
extension FocusBlock: StableModelIdentified {}
extension Attachment: StableModelIdentified {}

struct ObsidianImportReport: Equatable {
    var institutions = 0
    var people = 0
    var projects = 0
    var minutes = 0
    var documents = 0
    var notes = 0
    var dayRecords = 0
    var focusBlocks = 0
    var tasks = 0
    var attachments = 0
    var meetingEntries = 0
    var diagnostics = 0
}

@MainActor
struct ObsidianBundleImporter {
    let context: ModelContext
    let calendar: Calendar

    init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    func importBundle(from url: URL) throws -> ObsidianImportReport {
        let data = try Data(contentsOf: url)
        let bundle = try JSONDecoder().decode(ObsidianImportBundle.self, from: data)
        return try importBundle(bundle)
    }

    func importBundle(_ bundle: ObsidianImportBundle) throws -> ObsidianImportReport {
        var report = ObsidianImportReport(diagnostics: bundle.diagnostics.count)

        var institutions = try mapById(FetchDescriptor<Institution>())
        var people = try mapById(FetchDescriptor<Person>())
        var projects = try mapById(FetchDescriptor<Project>())
        var minutes = try mapById(FetchDescriptor<Minutes>())
        var documents = try mapById(FetchDescriptor<Document>())
        var notes = try mapById(FetchDescriptor<Note>())
        var dayRecords = try mapById(FetchDescriptor<DayRecord>())
        var tasks = try mapById(FetchDescriptor<Task>())
        var dayEntries = try mapById(FetchDescriptor<DayEntry>())
        var focusBlocks = try mapById(FetchDescriptor<FocusBlock>())
        var attachments = try mapById(FetchDescriptor<Attachment>())

        for imported in bundle.institutions {
            let institution = institutions[imported.id] ?? Institution(name: imported.name, id: imported.id)
            if institutions[imported.id] == nil { context.insert(institution); institutions[imported.id] = institution }
            institution.name = imported.name
            applyDates(created: imported.createdAt, updated: imported.updatedAt, to: institution)
            report.institutions += 1
        }

        for imported in bundle.people {
            let person = people[imported.id] ?? Person(name: imported.name, id: imported.id)
            if people[imported.id] == nil { context.insert(person); people[imported.id] = person }
            person.name = imported.name
            person.email = emptyToNil(imported.email)
            person.tags = imported.tags ?? []
            person.institution = imported.institutionId.flatMap { institutions[$0] }
            applyDates(created: imported.createdAt, updated: imported.updatedAt, to: person)
            report.people += 1
        }

        for imported in bundle.projects {
            let project = projects[imported.id] ?? Project(name: imported.name, id: imported.id)
            if projects[imported.id] == nil { context.insert(project); projects[imported.id] = project }
            project.name = imported.name
            project.projectDescription = emptyToNil(imported.description)
            project.stream = emptyToNil(imported.stream)
            project.isCompleted = imported.isCompleted ?? false
            project.tags = imported.tags ?? []
            project.parent = imported.parentProjectIds?.compactMap { projects[$0] }.first
            project.devTeam = imported.devTeamPersonIds?.compactMap { people[$0] } ?? []
            project.sciTeam = imported.sciTeamPersonIds?.compactMap { people[$0] } ?? []
            project.institutions = imported.institutionIds?.compactMap { institutions[$0] } ?? []
            applyDates(created: imported.createdAt, updated: imported.updatedAt, to: project)
            report.projects += 1
        }

        for imported in bundle.dayRecords {
            guard let date = parseDate(imported.date) else { continue }
            let record = dayRecords[imported.id] ?? DayRecord(date: date, id: imported.id)
            if dayRecords[imported.id] == nil { context.insert(record); dayRecords[imported.id] = record }
            record.date = calendar.startOfDay(for: date)
            record.focusTags = imported.tags ?? []
            applyDates(created: imported.createdAt, updated: imported.updatedAt, to: record)
            report.dayRecords += 1
        }

        for imported in bundle.notes {
            let note = notes[imported.id] ?? Note(content: imported.content ?? "", id: imported.id)
            if notes[imported.id] == nil { context.insert(note); notes[imported.id] = note }
            note.content = imported.content ?? ""
            note.blocks = imported.blocks?.map(makeNoteBlock) ?? [NoteBlock.text(imported.content ?? "")]
            note.tags = imported.tags ?? []
            note.dayRecord = imported.dayRecordId.flatMap { dayRecords[$0] }
            note.attachments = importNoteAttachments(imported, note: note, existing: &attachments, vaultPath: bundle.vaultPath)
            report.attachments += note.attachments.count
            applyDates(created: imported.createdAt, updated: imported.updatedAt, to: note)
            report.notes += 1
        }

        for imported in bundle.minutes {
            let item = minutes[imported.id] ?? Minutes(meetingAt: parseDate(imported.meetingAt) ?? Date(), id: imported.id)
            if minutes[imported.id] == nil { context.insert(item); minutes[imported.id] = item }
            item.summary = emptyToNil(imported.summary)
            item.meetingAt = parseDate(imported.meetingAt) ?? item.meetingAt
            item.duration = imported.duration?.domainDuration
            item.projects = imported.projectIds?.compactMap { projects[$0] } ?? []
            item.attendees = imported.attendeePersonIds?.compactMap { people[$0] } ?? []
            item.note = imported.noteId.flatMap { notes[$0] }
            applyDates(created: imported.createdAt, updated: imported.updatedAt, to: item)
            report.minutes += 1
        }

        for imported in bundle.documents {
            let document = documents[imported.id] ?? Document(id: imported.id, summary: imported.summary)
            if documents[imported.id] == nil { context.insert(document); documents[imported.id] = document }
            document.summary = emptyToNil(imported.summary)
            document.documentDescription = documentDescription(imported)
            document.projects = imported.projectIds?.compactMap { projects[$0] } ?? []
            document.attachments = importAttachments(imported, document: document, existing: &attachments, vaultPath: bundle.vaultPath)
            report.attachments += document.attachments.count
            applyDates(created: imported.createdAt, updated: imported.updatedAt, to: document)
            report.documents += 1
        }

        for imported in bundle.tasks {
            let task = tasks[imported.id] ?? Task(summary: imported.summary, id: imported.id)
            if tasks[imported.id] == nil { context.insert(task); tasks[imported.id] = task }
            task.summary = imported.summary
            task.notes = imported.notes.map(emptyToNil)
                ?? emptyToNil(imported.rawText).flatMap { $0 == imported.summary ? nil : $0 }
            task.status = imported.status
            task.tags = imported.tags ?? []
            task.duration = imported.duration?.domainDuration
            task.scheduledAt = parseDate(imported.scheduledAt)
            task.completedAt = parseDate(imported.completedAt)
            task.cancelledAt = parseDate(imported.cancelledAt)
            task.followUpAt = parseDate(imported.followUpAt)
            task.followedUpHistory = imported.followedUpHistory?.compactMap(parseDate) ?? []
            task.sourceContext = SourceContext(imported: imported.sourceContext)
            task.project = imported.projectId.flatMap { projects[$0] }
            task.assignee = imported.assigneePersonId.flatMap { people[$0] }
            task.originMinutes = imported.originMinutesId.flatMap { minutes[$0] }
            task.dayRecord = imported.dayRecordId.flatMap { dayRecords[$0] }
            task.originDay = task.dayRecord
            task.meetingTaskSortOrder = imported.line ?? 0
            task.sortOrder = imported.line ?? 0
            applyDates(created: imported.sourceContext?.externalSourceId.flatMap { _ in nil }, updated: nil, to: task)
            report.tasks += 1
        }

        for imported in bundle.focusBlocks ?? [] {
            let block = focusBlocks[imported.id]
                ?? FocusBlock(duration: imported.duration?.domainDuration ?? DaySlot.allDay.defaultDuration,
                              slot: imported.slot ?? .allDay,
                              sortOrder: imported.sortOrder ?? 0,
                              id: imported.id)
            if focusBlocks[imported.id] == nil { context.insert(block); focusBlocks[imported.id] = block }
            block.duration = imported.duration?.domainDuration ?? DaySlot.allDay.defaultDuration
            block.slot = imported.slot ?? .allDay
            block.sortOrder = imported.sortOrder ?? 0
            block.dayRecord = imported.dayRecordId.flatMap { dayRecords[$0] }

            let backingTask: Task
            if let taskId = imported.taskId {
                backingTask = tasks[taskId] ?? Task(summary: imported.summary, id: taskId)
                if tasks[taskId] == nil { context.insert(backingTask); tasks[taskId] = backingTask }
            } else {
                backingTask = Task(summary: imported.summary)
                context.insert(backingTask)
            }
            backingTask.summary = imported.summary
            backingTask.notes = emptyToNil(imported.rawText).flatMap { $0 == imported.summary ? nil : $0 }
            backingTask.tags = imported.tags ?? []
            backingTask.project = imported.projectId.flatMap { projects[$0] }
            backingTask.assignee = imported.assigneePersonId.flatMap { people[$0] }
            backingTask.originDay = block.dayRecord
            backingTask.sourceContext = SourceContext(imported: imported.sourceContext)
            block.task = backingTask
            block.project = imported.projectId.flatMap { projects[$0] }
            report.focusBlocks += 1
        }

        assignTaskParents(bundle.tasks, tasks: tasks)

        var dayRecordByDate = Dictionary(uniqueKeysWithValues: dayRecords.values.map { (dayKey($0.date), $0) })
        for item in minutes.values {
            let entryId = deterministicUUID("meeting-entry:\(item.id.uuidString)")
            let entry = dayEntries[entryId] ?? DayEntry(kind: .meeting, id: entryId)
            if dayEntries[entryId] == nil { context.insert(entry); dayEntries[entryId] = entry }
            let key = dayKey(item.meetingAt)
            let record = dayRecordByDate[key] ?? DayRecord(date: item.meetingAt, id: deterministicUUID("dayRecord:\(key)"))
            if dayRecordByDate[key] == nil {
                context.insert(record)
                dayRecords[record.id] = record
                dayRecordByDate[key] = record
                report.dayRecords += 1
            }
            entry.kind = .meeting
            entry.minutes = item
            entry.dayRecord = record
            entry.sortOrder = minutesSortOrder(item.meetingAt)
            entry.text = ""
            report.meetingEntries += 1
        }

        try context.save()
        return report
    }

    private func mapById<T: PersistentModel & StableModelIdentified>(_ descriptor: FetchDescriptor<T>) throws -> [UUID: T] {
        var result: [UUID: T] = [:]
        for item in try context.fetch(descriptor) {
            result[item.id] = item
        }
        return result
    }

    private func makeNoteBlock(_ imported: ImportedNoteBlock) -> NoteBlock {
        var block = imported.kind == .image
            ? NoteBlock.image(imported.attachmentId ?? UUID(), alignment: imported.alignment ?? .center)
            : NoteBlock.text(imported.textContent ?? "")
        block.groupId = imported.groupId
        return block
    }

    private func assignTaskParents(_ importedTasks: [ImportedTask], tasks: [UUID: Task]) {
        let groups = Dictionary(grouping: importedTasks) { $0.sourcePath ?? "" }
        for group in groups.values {
            var stack: [(indent: Int, task: Task)] = []
            for imported in group.sorted(by: { ($0.line ?? 0) < ($1.line ?? 0) }) {
                guard let task = tasks[imported.id] else { continue }
                let indent = imported.indent ?? 0
                while let last = stack.last, last.indent >= indent { stack.removeLast() }
                task.parent = stack.last?.task
                stack.append((indent, task))
            }
        }
    }

    private func documentDescription(_ imported: ImportedDocument) -> String? {
        var parts: [String] = []
        if let description = emptyToNil(imported.description) { parts.append(description) }
        if let refs = imported.attachmentRefs, !refs.isEmpty {
            parts.append("Imported attachment references:\n" + refs.map { "- \($0)" }.joined(separator: "\n"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    private func importAttachments(
        _ imported: ImportedDocument,
        document: Document,
        existing: inout [UUID: Attachment],
        vaultPath: String?
    ) -> [Attachment] {
        guard let refs = imported.attachmentRefs, !refs.isEmpty else { return [] }
        return refs.compactMap { ref in
            guard let sourceURL = resolveAttachment(ref, documentSource: imported.sourceContext?.sourceRecordId, vaultPath: vaultPath) else {
                return nil
            }
            let attachmentId = deterministicUUID("attachment:\(imported.id.uuidString):\(ref)")
            let attachment = existing[attachmentId] ?? Attachment(
                fileName: sourceURL.lastPathComponent,
                fileURL: sourceURL,
                kind: attachmentKind(for: sourceURL),
                id: attachmentId
            )
            if existing[attachmentId] == nil { context.insert(attachment); existing[attachmentId] = attachment }
            do {
                if attachment.fileURL == sourceURL || !FileManager.default.fileExists(atPath: attachment.fileURL.path) {
                    let dest = AttachmentStorage.attachmentsDirectory
                        .appendingPathComponent(attachmentId.uuidString)
                        .appendingPathExtension(sourceURL.pathExtension)
                    if FileManager.default.fileExists(atPath: dest.path) {
                        try? FileManager.default.removeItem(at: dest)
                    }
                    attachment.fileURL = try AttachmentStorage.store(from: sourceURL, fileId: attachmentId)
                }
                attachment.fileName = sourceURL.lastPathComponent
                attachment.kind = attachmentKind(for: sourceURL)
                attachment.fileSizeBytes = (try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                attachment.document = document
                if attachment.kind == .image {
                    attachment.sourceImageWidth = AttachmentStorage.capSource(at: attachment.fileURL)
                }
                return attachment
            } catch {
                return nil
            }
        }
    }

    private func importNoteAttachments(
        _ imported: ImportedNote,
        note: Note,
        existing: inout [UUID: Attachment],
        vaultPath: String?
    ) -> [Attachment] {
        guard let refs = imported.attachments, !refs.isEmpty else { return [] }
        return refs.compactMap { ref in
            guard let sourceURL = resolveAttachment(ref.ref, documentSource: imported.sourceContext?.sourceRecordId ?? imported.sourcePath, vaultPath: vaultPath) else {
                return nil
            }
            let attachment = existing[ref.id] ?? Attachment(
                fileName: ref.fileName ?? sourceURL.lastPathComponent,
                fileURL: sourceURL,
                kind: ref.kind ?? attachmentKind(for: sourceURL),
                id: ref.id
            )
            if existing[ref.id] == nil { context.insert(attachment); existing[ref.id] = attachment }
            do {
                if attachment.fileURL == sourceURL || !FileManager.default.fileExists(atPath: attachment.fileURL.path) {
                    let dest = AttachmentStorage.attachmentsDirectory
                        .appendingPathComponent(ref.id.uuidString)
                        .appendingPathExtension(sourceURL.pathExtension)
                    if FileManager.default.fileExists(atPath: dest.path) {
                        try? FileManager.default.removeItem(at: dest)
                    }
                    attachment.fileURL = try AttachmentStorage.store(from: sourceURL, fileId: ref.id)
                }
                attachment.fileName = ref.fileName ?? sourceURL.lastPathComponent
                attachment.kind = ref.kind ?? attachmentKind(for: sourceURL)
                attachment.fileSizeBytes = (try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                attachment.note = note
                if attachment.kind == .image {
                    attachment.sourceImageWidth = AttachmentStorage.capSource(at: attachment.fileURL)
                }
                return attachment
            } catch {
                return nil
            }
        }
    }

    private func resolveAttachment(_ ref: String, documentSource: String?, vaultPath: String?) -> URL? {
        let rawURL = URL(fileURLWithPath: ref)
        var candidates: [URL] = rawURL.path.hasPrefix("/") ? [rawURL] : []
        if let vaultPath {
            let vaultURL = URL(fileURLWithPath: vaultPath)
            candidates.append(vaultURL.appendingPathComponent(ref))
            if let documentSource {
                let sourceURL = vaultURL.appendingPathComponent(documentSource)
                candidates.append(sourceURL.deletingLastPathComponent().appendingPathComponent(ref))
                candidates.append(sourceURL.deletingPathExtension().appendingPathComponent(ref))
            }
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func attachmentKind(for url: URL) -> AttachmentKind {
        switch url.pathExtension.lowercased() {
        case "pdf": return .pdf
        case "png", "jpg", "jpeg", "gif", "heic", "tif", "tiff", "webp": return .image
        case "txt", "md", "csv", "json", "yaml", "yml": return .text
        default: return .other
        }
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        for format in ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return ISO8601DateFormatter().date(from: value)
    }

    private func applyDates(created: String?, updated: String?, to institution: Institution) {
        if let date = parseDate(created) { institution.createdAt = date }
        if let date = parseDate(updated) { institution.updatedAt = date }
    }

    private func applyDates(created: String?, updated: String?, to person: Person) {
        if let date = parseDate(created) { person.createdAt = date }
        if let date = parseDate(updated) { person.updatedAt = date }
    }

    private func applyDates(created: String?, updated: String?, to project: Project) {
        if let date = parseDate(created) { project.createdAt = date }
        if let date = parseDate(updated) { project.updatedAt = date }
    }

    private func applyDates(created: String?, updated: String?, to record: DayRecord) {
        if let date = parseDate(created) { record.createdAt = date }
        if let date = parseDate(updated) { record.updatedAt = date }
    }

    private func applyDates(created: String?, updated: String?, to note: Note) {
        if let date = parseDate(created) { note.createdAt = date }
        if let date = parseDate(updated) { note.updatedAt = date }
    }

    private func applyDates(created: String?, updated: String?, to minutes: Minutes) {
        if let date = parseDate(created) { minutes.createdAt = date }
        if let date = parseDate(updated) { minutes.updatedAt = date }
    }

    private func applyDates(created: String?, updated: String?, to document: Document) {
        if let date = parseDate(created) { document.createdAt = date }
        if let date = parseDate(updated) { document.updatedAt = date }
    }

    private func applyDates(created: String?, updated: String?, to task: Task) {
        if let date = parseDate(created) { task.createdAt = date }
        if let date = parseDate(updated) { task.updatedAt = date }
    }

    private func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func minutesSortOrder(_ date: Date) -> Int {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    private func deterministicUUID(_ key: String) -> UUID {
        let digest = SHA256.hash(data: Data(key.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private func emptyToNil(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
