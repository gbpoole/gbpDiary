import Foundation
import SwiftData

@Model final class Note {
    @Attribute(.unique) var id: UUID
    var title: String = ""       // free-standing "Content" notes have a non-empty title; day /
                                 // meeting / legacy project notes leave this empty — see
                                 // NoteContentMembership. Defaulted so lightweight migration can
                                 // backfill existing rows.
    var content: String          // markdown; sole source of truth. Images embed as
                                 // ![Display Name](attachment://<uuid>) — see AttachmentRef.
                                 // Note-to-note links embed as [Title](note://<uuid>) — NoteLinkRef.
    var sortOrder: Int
    var tagsJSON: String
    var tags: [String] {
        get { jsonDecode([String].self, tagsJSON) ?? [] }
        set { tagsJSON = jsonEncode(newValue) }
    }
    var createdAt: Date
    var updatedAt: Date

    var dayRecord: DayRecord?
    var project: Project?
    var minutes: Minutes?
    @Relationship(deleteRule: .cascade, inverse: \Attachment.note) var attachments: [Attachment]

    init(content: String = "", title: String = "", sortOrder: Int = 0, id: UUID = UUID()) {
        self.id = id
        self.title = title
        self.content = content
        self.sortOrder = sortOrder
        self.tagsJSON = "[]"
        self.attachments = []
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }

    /// Whether this note belongs to the free-standing "Content" vault.
    var isContentNote: Bool {
        NoteContentMembership.isContentNote(title: title,
                                            hasDayRecord: dayRecord != nil,
                                            hasMinutes: minutes != nil)
    }
}
