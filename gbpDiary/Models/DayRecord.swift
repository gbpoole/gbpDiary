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

    @Relationship(deleteRule: .cascade) var entries: [DayEntry]

    init(date: Date, id: UUID = UUID()) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.focusTagsJSON = "[]"
        self.entries = []
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }
}
