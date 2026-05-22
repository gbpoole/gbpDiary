import Foundation
import SwiftData

@Model final class Document {
    @Attribute(.unique) var id: UUID
    var documentDescription: String?
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Attachment.document)
    var attachments: [Attachment]

    @Relationship(inverse: \Project.documents)
    var projects: [Project]

    init(id: UUID = UUID()) {
        self.id = id
        self.attachments = []
        self.projects = []
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }
}
