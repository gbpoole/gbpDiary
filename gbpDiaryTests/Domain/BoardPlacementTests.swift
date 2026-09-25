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

    /// Triage is a gate, not something planning does for you: inbox work must be filed first.
    @Test func canPlace_requiresAnOpenTriagedTask() {
        #expect(BoardPlacement.canPlace(isOpen: true, needsTriage: false))
        #expect(!BoardPlacement.canPlace(isOpen: true, needsTriage: true))    // still in the inbox
        #expect(!BoardPlacement.canPlace(isOpen: false, needsTriage: false))  // finished
        #expect(!BoardPlacement.canPlace(isOpen: false, needsTriage: true))
    }

    /// Placing no longer reviews anything — it used to, and that rule was deliberately reversed.
    @Test func placingDoesNotReviewATask() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let task = Task(summary: "Write changelog")
        context.insert(task)
        #expect(task.needsTriage)

        task.place(on: .today)
        try context.save()
        #expect(task.needsTriage, "planning must not file a task for you")
    }

}
