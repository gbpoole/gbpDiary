import Foundation
import SwiftData

@Model final class Note {
    @Attribute(.unique) var id: UUID
    var content: String          // legacy; migrated into blocks on first open
    var blocksJSON: String = "[]"  // JSON-encoded [NoteBlock]; source of truth after migration
    var sortOrder: Int
    var tagsJSON: String
    var tags: [String] {
        get { jsonDecode([String].self, tagsJSON) ?? [] }
        set { tagsJSON = jsonEncode(newValue) }
    }
    var blocks: [NoteBlock] {
        get { jsonDecode([NoteBlock].self, blocksJSON) ?? [] }
        set { blocksJSON = jsonEncode(newValue) }
    }
    var createdAt: Date
    var updatedAt: Date

    var dayRecord: DayRecord?
    var project: Project?
    var minutes: Minutes?
    @Relationship(deleteRule: .cascade, inverse: \Attachment.note) var attachments: [Attachment]

    init(content: String = "", sortOrder: Int = 0, id: UUID = UUID()) {
        self.id = id
        self.content = content
        self.sortOrder = sortOrder
        self.tagsJSON = "[]"
        self.attachments = []
        let initialBlock = NoteBlock.text(content)
        self.blocksJSON = jsonEncode([initialBlock])
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }
}
