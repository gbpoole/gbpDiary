import Foundation
import SwiftData

@Model final class FocusBlock {
    @Attribute(.unique) var id: UUID
    var duration: Duration
    // Optional backing store allows lightweight migration from existing rows (nil → allDay).
    private var slotRaw: DaySlot?
    var sortOrder: Int
    var createdAt: Date

    // Singular-side relationships — collection side declares @Relationship(inverse:)
    var task: Task?
    var project: Project?
    var dayRecord: DayRecord?

    @Relationship(deleteRule: .nullify, inverse: \TaskTimeEntry.focusBlock)
    var activities: [TaskTimeEntry]

    var slot: DaySlot {
        get { slotRaw ?? .allDay }
        set { slotRaw = newValue }
    }

    var displayLabel: String {
        task?.summary ?? project?.name ?? "Focus block"
    }

    var netHours: Double {
        let spent = activities.reduce(0.0) { $0 + $1.duration.hoursNormalized }
        return max(0, duration.hoursNormalized - spent)
    }

    init(duration: Duration, slot: DaySlot = .allDay, sortOrder: Int = 0, id: UUID = UUID()) {
        self.id = id
        self.duration = duration
        self.slotRaw = slot == .allDay ? nil : slot
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.activities = []
    }
}
