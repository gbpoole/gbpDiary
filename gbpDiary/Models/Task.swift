import Foundation
import SwiftData

// Named `Task` to match the domain spec. Swift concurrency's Task can be
// accessed as `Swift.Task { }` when needed in the same file.
@Model final class Task {
    @Attribute(.unique) var id: UUID
    var summary: String
    var taskDescription: String?
    var status: TaskStatus
    var duration: Duration?
    var scheduledAt: Date?
    var completedAt: Date?
    var cancelledAt: Date?
    var followUpAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var sourceContext: SourceContext?

    // Array attributes stored as JSON strings (CoreData cannot materialize Array<T>)
    var tagsJSON: String
    var followedUpHistoryJSON: String

    var tags: [String] {
        get { jsonDecode([String].self, tagsJSON) ?? [] }
        set { tagsJSON = jsonEncode(newValue) }
    }

    var followedUpHistory: [Date] {
        get { jsonDecode([Date].self, followedUpHistoryJSON) ?? [] }
        set { followedUpHistoryJSON = jsonEncode(newValue) }
    }

    var assignee: Person?
    var project: Project?
    var originDay: DayRecord?
    var parent: Task?
    @Relationship(deleteRule: .cascade)
    var children: [Task]

    init(
        summary: String,
        id: UUID = UUID(),
        status: TaskStatus = .todo,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.summary = summary
        self.status = status
        self.tagsJSON = "[]"
        self.followedUpHistoryJSON = "[]"
        self.children = []
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

extension Task {
    func markCompleted() {
        let now = Date()
        status = .completed
        completedAt = now
        cancelledAt = nil
        updatedAt = now
    }

    func unmarkCompleted() {
        status = .todo
        completedAt = nil
        updatedAt = Date()
    }

    func markCancelled() {
        let now = Date()
        status = .cancelled
        cancelledAt = now
        completedAt = nil
        updatedAt = now
    }

    func unmarkCancelled() {
        status = .todo
        cancelledAt = nil
        updatedAt = Date()
    }

    func setFollowUp(date: Date) {
        followUpAt = date
        status = .followUpPending
        updatedAt = Date()
    }

    func markFollowUpDone() {
        if let due = followUpAt {
            followedUpHistory = followedUpHistory + [due]
        }
        followUpAt = nil
        status = .completed
        if completedAt == nil { completedAt = Date() }
        updatedAt = Date()
    }

    func setDuration(_ dur: Duration) {
        duration = dur
        if completedAt == nil && (status == .todo || status == .started) {
            markCompleted()
        }
        updatedAt = Date()
    }
}
