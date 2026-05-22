import Foundation
import SwiftData

@Model final class Note {
    @Attribute(.unique) var id: UUID
    var content: String
    var createdAt: Date
    var updatedAt: Date

    init(content: String, id: UUID = UUID()) {
        self.id = id
        self.content = content
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }
}
