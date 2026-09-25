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

        let buckets = BoardPartition.partition([task], needsTriage: \.needsTriage,
                                               isStanding: \.isStanding, isOpen: \.isOpen,
                                               horizon: \.planHorizon, sortOrder: \.planSortOrder)
        #expect(buckets.inbox.isEmpty)
        #expect(buckets.today.map(\.id) == [task.id])
    }

    /// Standing tasks are never planned, so placing must not sneak one onto the board.
    @Test func standingTaskStaysOffTheBoard() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let task = Task(summary: "Keep inbox at zero")
        context.insert(task)
        task.makeStanding()
        task.place(on: .today)            // no-op for standing tasks
        try context.save()

        let buckets = BoardPartition.partition([task], needsTriage: \.needsTriage,
                                               isStanding: \.isStanding, isOpen: \.isOpen,
                                               horizon: \.planHorizon, sortOrder: \.planSortOrder)
        #expect(buckets.today.isEmpty)
        #expect(buckets.inbox.isEmpty)
    }
}
