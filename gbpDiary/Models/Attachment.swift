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
    /// User-chosen display width as a percent of the note's available width (1–100) for previews;
    /// nil = 100% / fit to the pane (default). The original full-resolution file is always retained
    /// for export/download.
    var displayWidthPercent: Int?

    var document: Document?
    var note: Note?

    // Comparable sort keys for the Image library table columns (see the List/Table page style in CLAUDE.md).
    /// The name shown in the library: the display name, falling back to the file name.
    var libraryName: String { displayName ?? fileName }
    var nameKey: String { libraryName.lowercased() }
    var descriptionKey: String { (attachmentDescription ?? "").lowercased() }
    var sizeSortKey: Int { fileSizeBytes ?? 0 }

    init(fileName: String, fileURL: URL, kind: AttachmentKind, id: UUID = UUID()) {
        self.id = id
        self.fileName = fileName
        self.fileURL = fileURL
        self.kind = kind
        self.createdAt = Date()
    }
}
