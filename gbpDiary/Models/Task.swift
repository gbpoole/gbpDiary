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
    // Deadline (distinct from `scheduledAt`, which is when you plan to work it). Defaulted for migration.
    var dueAt: Date?
    // Raw of TaskPriority; use the `priority` computed accessor.
    var priorityRaw: String = TaskPriority.none.rawValue
    var completedAt: Date?
    var cancelledAt: Date?
    var followUpAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var sourceContext: SourceContext?
    // Task inbox/triage: a new task must be explicitly Reviewed before it leaves the inbox and appears
    // in the normal (Reviewed) task list. Stored default `false` so existing rows migrate as already
    // triaged; `init` sets it `true` so every newly-created task needs triage. See `markReviewed()`.
    var needsTriage: Bool = false

    // Standing task: a stateless, perpetual, per-project time bucket (e.g. "review email"). It has no
    // cyclable status, accumulates time, is exempt from overdue/urgency nagging, never appears on the
    // planning board, and is created already-reviewed. Defaulted for migration.
    var isStanding: Bool = false

    // Planning-board placement. `planHorizonRaw` backs the optional `planHorizon` (nil = not on the
    // board). `planSortOrder` orders tasks within a board section. Both defaulted for migration.
    var planHorizonRaw: String?
    var planSortOrder: Int = 0

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
    var originEmail: EmailMessage?   // LEGACY email backbone (EmailMessage.tasks inverse); provenance now reads via `source`
    // Unified provenance — where this task came from (email/slack/web/other). Cascade: deleting the task
    // deletes its source. For email, coexists with `originEmail` (which still powers the email inverse).
    @Relationship(deleteRule: .cascade, inverse: \TaskSource.task) var source: TaskSource?
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

    // Dependencies (self many-to-many): this task is blocked until every task in `dependsOn` is done.
    // `blocking` is the inverse (tasks that depend on this one). Nullify so deleting a task just drops
    // the edges.
    @Relationship(deleteRule: .nullify) var dependsOn: [Task] = []
    @Relationship(deleteRule: .nullify, inverse: \Task.dependsOn) var blocking: [Task] = []

    // Deferral + recurrence (all defaulted for migration).
    var waitUntil: Date?               // hidden from lists until this date
    var until: Date?                   // auto-cancelled once past this date
    var recurrenceRule: String?        // e.g. "1w"/"2mo" — completing spawns the next instance
    var recurrenceParentID: UUID?      // lineage: the task this instance was spawned from

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
        self.needsTriage = true   // every newly-created task lands in the inbox until Reviewed
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

    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue; updatedAt = Date() }
    }

    /// Planning-board horizon (nil = not placed on the board). Setting also clears when nil.
    var planHorizon: PlanHorizon? {
        get { planHorizonRaw.flatMap(PlanHorizon.init(rawValue:)) }
        set { planHorizonRaw = newValue?.rawValue; updatedAt = Date() }
    }

    /// Open and past its due date (day-granularity). Standing tasks never nag as overdue.
    var isOverdue: Bool { !isStanding && TaskFlags.isOverdue(dueAt: dueAt, isOpen: isOpen) }
    var isDueToday: Bool { TaskFlags.isDueToday(dueAt: dueAt) }

    /// Blocked while any prerequisite is still open (completing a blocker auto-unblocks — derived).
    var isBlocked: Bool { dependsOn.contains(where: \.isOpen) }
    /// This task blocks another still-open task.
    var isBlocking: Bool { blocking.contains(where: \.isOpen) }

    /// Deferred: hidden from lists until `waitUntil`.
    var isWaiting: Bool { TaskFlags.isWaiting(waitUntil: waitUntil) }

    func markCompleted() {
        let now = Date()
        status = .completed
        if completedAt == nil { completedAt = now }
        updatedAt = now
    }

    /// Clear the inbox/triage flag (the task has been Reviewed) so it enters the normal task list.
    func markReviewed() {
        guard needsTriage else { return }
        needsTriage = false
        updatedAt = Date()
    }

    /// Turn this into a stateless standing task: perpetual, exempt from nagging, off the board, and
    /// already-reviewed (never blocks a project's tasks-reviewed gate). Idempotent.
    func makeStanding() {
        isStanding = true
        needsTriage = false
        planHorizonRaw = nil
        updatedAt = Date()
    }

    /// Place (or clear) the task on the planning board. Standing tasks never go on the board.
    func place(on horizon: PlanHorizon?) {
        guard !isStanding else { return }
        planHorizon = horizon   // setter bumps updatedAt
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
