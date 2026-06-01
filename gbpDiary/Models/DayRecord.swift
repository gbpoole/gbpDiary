import Foundation
import SwiftData

@Model final class DayRecord {
    @Attribute(.unique) var id: UUID
    var date: Date
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    // Stored as JSON string — see ValueTypes.swift for why
    var focusTagsJSON: String

    var focusTags: [String] {
        get { jsonDecode([String].self, focusTagsJSON) ?? [] }
        set { focusTagsJSON = jsonEncode(newValue) }
    }

    @Relationship(deleteRule: .cascade, inverse: \DayEntry.dayRecord) var entries: [DayEntry]
    @Relationship(deleteRule: .nullify, inverse: \Task.dayRecord) var tasks: [Task]

    init(date: Date, id: UUID = UUID()) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.focusTagsJSON = "[]"
        self.entries = []
        self.tasks = []
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }
}
