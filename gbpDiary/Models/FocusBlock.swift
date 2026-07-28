import Foundation
import SwiftData

@Model final class FocusBlock {
    @Attribute(.unique) var id: UUID
    var duration: Duration
    // Optional backing store allows lightweight migration from existing rows (nil → allDay).
    private var slotRaw: DaySlot?
    var sortOrder: Int
    var createdAt: Date
    // Flexible wall-clock start for an evening block (nil for other slots). Default 18:00.
    var startTime: Date?
    // Optional free-text note for the block (like a TaskTimeEntry comment).
    var comment: String? = nil

    // Singular-side relationships — collection side declares @Relationship(inverse:)
    var task: Task?
    var project: Project?
    var dayRecord: DayRecord?

    var slot: DaySlot {
        get { slotRaw ?? .allDay }
        set { slotRaw = newValue }
    }

    var displayLabel: String {
        task?.summary ?? project?.name ?? slot.displayName
    }

    var isOvertime: Bool { slot.isOvertime }

    // Net-remaining is computed at the view layer from the block's time-derived entries — see
    // FocusBlockMath.netHours and FocusBlockRow. Membership is never stored (FocusBlockAssignment).

    init(duration: Duration, slot: DaySlot = .allDay, comment: String? = nil, sortOrder: Int = 0, id: UUID = UUID()) {
        self.id = id
        self.duration = duration
        self.slotRaw = slot == .allDay ? nil : slot
        self.comment = comment
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }
}
