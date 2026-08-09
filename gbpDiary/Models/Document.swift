import Foundation
import SwiftData

@Model final class Document {
    @Attribute(.unique) var id: UUID
    var summary: String?
    var documentDescription: String?
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Attachment.document)
    var attachments: [Attachment]

    @Relationship(inverse: \Project.documents)
    var projects: [Project]

    var meetings: [Minutes]

    var dayRecord: DayRecord?

    // Comparable sort keys for the Documents table columns (see the List/Table page style in CLAUDE.md).
    // The Created column sorts by `createdAt` directly.
    var summaryKey: String { (summary ?? "").lowercased() }
    var descriptionKey: String { (documentDescription ?? "").lowercased() }
    var projectsKey: String { projects.map(\.name).sorted().joined(separator: ", ").lowercased() }
    var attachmentCount: Int { attachments.count }

    init(id: UUID = UUID(), summary: String? = nil) {
        self.id = id
        self.summary = summary
        self.attachments = []
        self.projects = []
        self.meetings = []
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }
}
