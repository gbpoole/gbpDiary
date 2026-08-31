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
    // When set, this entry logs time spent on a sent email (no task); EmailMessage declares the inverse.
    var email: EmailMessage?
    // When set, this entry logs time against an email conversation (the conversation owns its time);
    // EmailConversation declares the inverse.
    var conversation: EmailConversation?

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
