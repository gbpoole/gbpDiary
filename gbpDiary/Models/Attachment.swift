import Foundation
import SwiftData

enum AttachmentKind: String, Codable {
    case pdf, image, text, other
}

@Model final class Attachment {
    @Attribute(.unique) var id: UUID
    var fileName: String
    var fileURL: URL           // path within app container (copied via AttachmentStorage.store)
    var bookmarkData: Data?    // unused for new attachments; reserved for migrating pre-existing bookmarks
    var kind: AttachmentKind
    var mimeType: String?
    var fileSizeBytes: Int?
    var createdAt: Date

    var displayName: String?           // user-facing name shown on screen / used as markdown alt text
    var attachmentDescription: String? // optional longer description of the image's contents/relevance

    var document: Document?
    var note: Note?

    init(fileName: String, fileURL: URL, kind: AttachmentKind, id: UUID = UUID()) {
        self.id = id
        self.fileName = fileName
        self.fileURL = fileURL
        self.kind = kind
        self.createdAt = Date()
    }
}
