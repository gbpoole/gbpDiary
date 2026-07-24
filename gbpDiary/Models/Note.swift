import Foundation
import SwiftData

@Model final class Note {
    @Attribute(.unique) var id: UUID
    var content: String          // markdown; sole source of truth. Images embed as
                                 // ![Display Name](attachment://<uuid>) — see AttachmentRef.
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

    init(content: String = "", sortOrder: Int = 0, id: UUID = UUID()) {
        self.id = id
        self.content = content
        self.sortOrder = sortOrder
        self.tagsJSON = "[]"
        self.attachments = []
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }
}
