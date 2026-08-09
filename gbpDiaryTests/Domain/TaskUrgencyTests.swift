import Testing
import Foundation
@testable import gbpDiary

@Suite("TaskUrgency")
struct TaskUrgencyTests {
    private let now = Date(timeIntervalSince1970: 1_770_000_000)
    private func base() -> UrgencyInputs {
        UrgencyInputs(dueAt: nil, priorityWeight: 0, ageDays: 0, isActive: false,
                      isScheduledNow: false, hasTags: false, hasProject: false,
                      isBlocked: false, isBlocking: false, isWaiting: false)
    }

    @Test func dueUrgency_rampsAndClamps() {
        let overdue = TaskUrgency.dueUrgency(now.addingTimeInterval(-8 * 86400), now: now)   // 8 days overdue
        let soon    = TaskUrgency.dueUrgency(now.addingTimeInterval(2 * 86400), now: now)    // 2 days out
        let far     = TaskUrgency.dueUrgency(now.addingTimeInterval(60 * 86400), now: now)   // 60 days out
        #expect(overdue == 1.0)
        #expect(far == 0.2)
        #expect(soon > far && soon < overdue)
        #expect(TaskUrgency.dueUrgency(nil, now: now) == 0)
    }

    @Test func priority_increasesUrgency() {
        var lo = base(); lo.priorityWeight = TaskPriority.low.weight
        var hi = base(); hi.priorityWeight = TaskPriority.high.weight
        #expect(TaskUrgency.score(hi, now: now) > TaskUrgency.score(lo, now: now))
    }

    @Test func blocked_penalises_blocking_boosts() {
        var blocked = base(); blocked.isBlocked = true
        var blocking = base(); blocking.isBlocking = true
        #expect(TaskUrgency.score(blocked, now: now) < TaskUrgency.score(base(), now: now))
        #expect(TaskUrgency.score(blocking, now: now) > TaskUrgency.score(base(), now: now))
    }

    @Test func activeAndScheduled_addUrgency() {
        var active = base(); active.isActive = true
        var sched = base(); sched.isScheduledNow = true
        #expect(TaskUrgency.score(active, now: now) == TaskUrgency.score(base(), now: now) + TaskUrgency.cActive)
        #expect(TaskUrgency.score(sched, now: now) == TaskUrgency.score(base(), now: now) + TaskUrgency.cScheduled)
    }

    @Test func waiting_penalises() {
        var waiting = base(); waiting.isWaiting = true
        #expect(TaskUrgency.score(waiting, now: now) < TaskUrgency.score(base(), now: now))
    }

    @Test func notOpen_scoresZero() {
        var done = base()
        done.isOpen = false
        done.priorityWeight = TaskPriority.high.weight
        done.dueAt = now.addingTimeInterval(-100 * 86400)   // very overdue + high priority
        #expect(TaskUrgency.score(done, now: now) == 0)      // …still zero because it's finished
    }

    @Test func effectiveDue_usesPendingFollowUpAndEarliest() {
        let due = now.addingTimeInterval(10 * 86400)
        let follow = now.addingTimeInterval(2 * 86400)
        // Pending follow-up counts, and the earliest of the two wins.
        #expect(TaskUrgency.effectiveDue(dueAt: due, followUpAt: follow, isFollowUpPending: true) == follow)
        // Follow-up ignored when the task isn't in follow-up.
        #expect(TaskUrgency.effectiveDue(dueAt: due, followUpAt: follow, isFollowUpPending: false) == due)
        #expect(TaskUrgency.effectiveDue(dueAt: nil, followUpAt: follow, isFollowUpPending: true) == follow)
        #expect(TaskUrgency.effectiveDue(dueAt: nil, followUpAt: nil, isFollowUpPending: true) == nil)
    }

    @Test func ordering_overdueHighPriorityFloatsAbovePlain() {
        var urgent = base(); urgent.dueAt = now.addingTimeInterval(-2 * 86400); urgent.priorityWeight = TaskPriority.high.weight
        let plain = base()
        #expect(TaskUrgency.score(urgent, now: now) > TaskUrgency.score(plain, now: now))
    }
}
