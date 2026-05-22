import Foundation
import SwiftData

@Model final class DayRecord {
    @Attribute(.unique) var id: UUID
    var date: Date
    var notes: String?
    var focusTags: [String]
    var createdAt: Date
    var updatedAt: Date

    init(date: Date, id: UUID = UUID()) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.focusTags = []
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }
}
