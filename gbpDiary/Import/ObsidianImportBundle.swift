import Foundation

struct ObsidianImportBundle: Decodable {
    var schemaVersion: Int
    var generatedAt: String?
    var vaultPath: String?
    var counts: [String: Int]
    var institutions: [ImportedInstitution]
    var people: [ImportedPerson]
    var projects: [ImportedProject]
    var minutes: [ImportedMinutes]
    var documents: [ImportedDocument]
    var notes: [ImportedNote]
    var dayRecords: [ImportedDayRecord]
    var focusBlocks: [ImportedFocusBlock]?
    var tasks: [ImportedTask]
    var diagnostics: [ImportedDiagnostic]
}

struct ImportedSourceContext: Decodable {
    var externalSourceId: String?
    var sourceRecordId: String?
    var sourceSection: String?
    var sourceLineFingerprint: String?
}

struct ImportedDuration: Decodable {
    var value: Double
    var unit: DurationUnit
    var hoursNormalized: Double

    var domainDuration: Duration { Duration(value: value, unit: unit) }
}

struct ImportedInstitution: Decodable {
    var id: UUID
    var name: String
    var createdAt: String?
    var updatedAt: String?
    var sourceContext: ImportedSourceContext?
}

struct ImportedPerson: Decodable {
    var id: UUID
    var name: String
    var email: String?
    var institutionId: UUID?
    var tags: [String]?
    var createdAt: String?
    var updatedAt: String?
    var sourceContext: ImportedSourceContext?
}

struct ImportedProject: Decodable {
    var id: UUID
    var name: String
    var description: String?
    var stream: String?
    var isCompleted: Bool?
    var parentProjectIds: [UUID]?
    var devTeamPersonIds: [UUID]?
    var sciTeamPersonIds: [UUID]?
    var institutionIds: [UUID]?
    var tags: [String]?
    var createdAt: String?
    var updatedAt: String?
    var sourceContext: ImportedSourceContext?
}

struct ImportedMinutes: Decodable {
    var id: UUID
    var summary: String?
    var meetingAt: String?
    var duration: ImportedDuration?
    var projectIds: [UUID]?
    var attendeePersonIds: [UUID]?
    var noteId: UUID?
    var createdAt: String?
    var updatedAt: String?
    var sourceContext: ImportedSourceContext?
}

struct ImportedDocument: Decodable {
    var id: UUID
    var summary: String?
    var description: String?
    var projectIds: [UUID]?
    var attachmentRefs: [String]?
    var createdAt: String?
    var updatedAt: String?
    var sourceContext: ImportedSourceContext?
}

struct ImportedNoteBlock: Decodable {
    var kind: NoteBlockKind
    var textContent: String?
    var attachmentId: UUID?
    var alignment: ImageAlignment?
    var groupId: UUID?
}

struct ImportedNote: Decodable {
    var id: UUID
    var content: String?
    var blocks: [ImportedNoteBlock]?
    var dayRecordId: UUID?
    var sourcePath: String?
    var createdAt: String?
    var updatedAt: String?
    var sourceContext: ImportedSourceContext?
}

struct ImportedDayRecord: Decodable {
    var id: UUID
    var date: String
    var createdAt: String?
    var updatedAt: String?
    var sourceContext: ImportedSourceContext?
}

struct ImportedFocusBlock: Decodable {
    var id: UUID
    var summary: String
    var rawText: String?
    var duration: ImportedDuration?
    var slot: DaySlot?
    var sortOrder: Int?
    var taskId: UUID?
    var projectId: UUID?
    var assigneePersonId: UUID?
    var dayRecordId: UUID?
    var sourceContext: ImportedSourceContext?
}

struct ImportedTask: Decodable {
    var id: UUID
    var summary: String
    var rawText: String?
    var status: TaskStatus
    var tags: [String]?
    var duration: ImportedDuration?
    var scheduledAt: String?
    var completedAt: String?
    var cancelledAt: String?
    var followUpAt: String?
    var followedUpHistory: [String]?
    var indent: Int?
    var line: Int?
    var section: String?
    var sourcePath: String?
    var sourceType: String?
    var inlineFields: [String: String]?
    var projectId: UUID?
    var assigneePersonId: UUID?
    var minutesId: UUID?
    var originMinutesId: UUID?
    var dayRecordId: UUID?
    var sourceContext: ImportedSourceContext?
}

struct ImportedDiagnostic: Decodable {
    var severity: String
    var code: String
    var source: String?
    var expectedType: String?
    var value: String?
}

extension SourceContext {
    init(imported: ImportedSourceContext?) {
        self.init(
            externalSourceId: imported?.externalSourceId,
            sourceRecordId: imported?.sourceRecordId,
            sourceSection: imported?.sourceSection,
            sourceLineFingerprint: imported?.sourceLineFingerprint,
            importRunId: nil,
            firstSeenAt: nil,
            lastSeenAt: nil
        )
    }
}
