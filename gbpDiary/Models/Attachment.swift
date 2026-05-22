import Foundation
import SwiftData

enum AttachmentKind: String, Codable {
    case pdf, image, other
}

@Model final class Attachment {
    @Attribute(.unique) var id: UUID
    var fileName: String
    var fileURL: URL
    var bookmarkData: Data?
    var kind: AttachmentKind
    var mimeType: String?
    var fileSizeBytes: Int?
    var createdAt: Date

    var document: Document?

    init(fileName: String, fileURL: URL, kind: AttachmentKind, id: UUID = UUID()) {
        self.id = id
        self.fileName = fileName
        self.fileURL = fileURL
        self.kind = kind
        self.createdAt = Date()
    }
}
