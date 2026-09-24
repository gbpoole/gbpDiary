    /// Standing tasks ARE planned now: perpetual work such as "Triage Emails" belongs in a day. Since
    /// it never completes, it leaves a lane only by being removed.
    @Test func standingTaskCanBePlaced() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let task = Task(summary: "Triage Emails")
        context.insert(task)
        task.makeStanding()
        task.place(on: .today)
        try context.save()

        #expect(task.planHorizon == .today, "makeStanding must not strip a horizon either")
        let buckets = BoardPartition.partition([task], isOpen: \.isOpen,
                                               horizon: \.planHorizon, sortOrder: \.planSortOrder)
        #expect(buckets.today.map(\.id) == [task.id])
    }
import Foundation
import SwiftData
import Testing
@testable import gbpDiary

@MainActor
struct BoardPlacementTests {

    @Test func appendOrder_goesAfterEverythingInTheColumn() {
        #expect(BoardPlacement.appendOrder(existingOrders: []) == 0)
        #expect(BoardPlacement.appendOrder(existingOrders: [0, 1, 2]) == 3)
        #expect(BoardPlacement.appendOrder(existingOrders: [5, 2]) == 6)   // max, not count
        #expect(BoardPlacement.appendOrder(existingOrders: [-3]) == -2)
    }

    @Test func shouldReview_onlyWhenComingFromTheInbox() {
        #expect(BoardPlacement.shouldReview(needsTriage: true))
        #expect(!BoardPlacement.shouldReview(needsTriage: false))
    }

    /// Placing an inbox task plans it and reviews it in one move, so it leaves the Inbox column.
    @Test func placingAnInboxTask_reviewsItAndLeavesTheInbox() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let task = Task(summary: "Write changelog")
        context.insert(task)
        #expect(task.needsTriage)

        if BoardPlacement.shouldReview(needsTriage: task.needsTriage) {
            task.place(on: .today)
            task.markReviewed()
        }
        try context.save()

        #expect(task.planHorizon == .today)
        #expect(!task.needsTriage)

        let buckets = BoardPartition.partition([task], isOpen: \.isOpen,
                                               horizon: \.planHorizon, sortOrder: \.planSortOrder)
        #expect(buckets.today.map(\.id) == [task.id])
    }

}
