import Foundation
import SwiftData

// Named `Task` to match the domain spec. Swift concurrency's Task can be
// accessed as `Swift.Task { }` when needed in the same file.
@Model final class Task {
    @Attribute(.unique) var id: UUID
    var summary: String
    var notes: String?
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
    var originMinutes: Minutes?
    var originEmail: EmailMessage?   // set when the task was made from a triaged email (EmailMessage declares the inverse)
    var meetingTaskSortOrder: Int = 0
    var parent: Task?
    @Relationship(deleteRule: .cascade, inverse: \Task.parent)
    var children: [Task]

    // Explicit container ownership — set on root tasks (parent == nil).
    // Exactly one of these is non-nil for a root task; all nil = backlog.
    var dayRecord: DayRecord?
    var institution: Institution?

    // Ordering within the diary (root tasks) or among siblings within a parent.
    var sortOrder: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \TaskTimeEntry.task)
    var timeEntries: [TaskTimeEntry]

    @Relationship(deleteRule: .nullify, inverse: \FocusBlock.task)
    var focusBlocks: [FocusBlock]

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
        self.timeEntries = []
        self.focusBlocks = []
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

extension Task {
    var loggedHoursNormalized: Double {
        timeEntries.reduce(0.0) { $0 + $1.duration.hoursNormalized }
    }

    var loggedDuration: Duration? {
        guard !timeEntries.isEmpty else { return nil }
        return Duration(value: loggedHoursNormalized, unit: .h)
    }

    var needsChevron: Bool {
        !children.isEmpty || (notes.map { !$0.isEmpty } ?? false)
    }

    /// Not yet finished (i.e. still actionable): status is neither completed nor cancelled.
    var isOpen: Bool { status != .completed && status != .cancelled }

    func markCompleted() {
        let now = Date()
        status = .completed
        if completedAt == nil { completedAt = now }
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
        if cancelledAt == nil { cancelledAt = now }
        followUpAt = nil
        updatedAt = now
    }

    func unmarkCancelled() {
        status = .todo
        cancelledAt = nil
        followUpAt = nil
        updatedAt = Date()
    }

    func clearFollowUp() {
        followUpAt = nil
        if status == .followUpPending { status = .completed }
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
