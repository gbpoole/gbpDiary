import Foundation
import SwiftData

@Model final class DayEntry {
    @Attribute(.unique) var id: UUID
    var kind: DayEntryKind
    var text: String
    var sortOrder: Int
    var indentLevel: Int
    var createdAt: Date

    var dayRecord: DayRecord?
    var task: Task?
    var minutes: Minutes?
    var project: Project?
    var duration: Duration?

    init(kind: DayEntryKind, text: String = "", sortOrder: Int = 0, indentLevel: Int = 0, id: UUID = UUID()) {
        self.id = id
        self.kind = kind
        self.text = text
        self.sortOrder = sortOrder
        self.indentLevel = indentLevel
        self.createdAt = Date()
    }
}
