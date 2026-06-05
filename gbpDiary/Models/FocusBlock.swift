import Foundation
import SwiftData

@Model final class FocusBlock {
    @Attribute(.unique) var id: UUID
    var duration: Duration
    var sortOrder: Int
    var createdAt: Date

    // Singular-side relationships — collection side declares @Relationship(inverse:)
    var task: Task?
    var project: Project?
    var dayRecord: DayRecord?

    @Relationship(deleteRule: .nullify, inverse: \TaskTimeEntry.focusBlock)
    var activities: [TaskTimeEntry]

    var displayLabel: String {
        task?.summary ?? project?.name ?? "Focus block"
    }

    var netHours: Double {
        let spent = activities.reduce(0.0) { $0 + $1.duration.hoursNormalized }
        return max(0, duration.hoursNormalized - spent)
    }

    init(duration: Duration, sortOrder: Int = 0, id: UUID = UUID()) {
        self.id = id
        self.duration = duration
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.activities = []
    }
}
