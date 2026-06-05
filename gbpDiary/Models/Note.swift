import Foundation
import SwiftData

@Model final class Note {
    @Attribute(.unique) var id: UUID
    var content: String
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

    init(content: String = "", sortOrder: Int = 0, id: UUID = UUID()) {
        self.id = id
        self.content = content
        self.sortOrder = sortOrder
        self.tagsJSON = "[]"
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }
}
