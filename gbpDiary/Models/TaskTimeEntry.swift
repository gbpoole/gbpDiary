import Foundation
import SwiftData

@Model final class TaskTimeEntry {
    @Attribute(.unique) var id: UUID
    var date: Date
    var duration: Duration
    var comment: String?
    var sortOrder: Int
    var createdAt: Date

    // Singular-side relationship — Task declares the inverse. Block membership is derived by time
    // at the view layer (FocusBlockAssignment), never stored.
    var task: Task?

    init(date: Date, duration: Duration, comment: String? = nil,
         sortOrder: Int = 0, id: UUID = UUID()) {
        self.id = id
        self.date = date
        self.duration = duration
        self.comment = comment
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }
}
