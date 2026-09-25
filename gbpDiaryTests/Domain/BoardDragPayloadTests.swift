import Foundation
import SwiftData
import Testing
@testable import gbpDiary

struct BoardDragPayloadTests {

    @Test func roundTripsASingleID() {
        let id = UUID()
        #expect(BoardDragPayload.decode([BoardDragPayload.encode([id])]) == [id])
    }

    /// The whole point: one drag carrying a multi-card selection.
    @Test func roundTripsAManyIDSelectionInOrder() {
        let ids = [UUID(), UUID(), UUID()]
        #expect(BoardDragPayload.decode([BoardDragPayload.encode(ids)]) == ids)
    }

    @Test func flattensSeveralPayloads() {
        let a = UUID(), b = UUID(), c = UUID()
        let decoded = BoardDragPayload.decode([BoardDragPayload.encode([a, b]),
                                               BoardDragPayload.encode([c])])
        #expect(decoded == [a, b, c])
    }

    @Test func dropsRepeatsAndKeepsFirstPosition() {
        let a = UUID(), b = UUID()
        #expect(BoardDragPayload.decode([BoardDragPayload.encode([a, b, a])]) == [a, b])
    }

    /// A drag from elsewhere in the app (or a stray text drop) must not crash or half-apply.
    @Test func ignoresUnparseablePieces() {
        let id = UUID()
        #expect(BoardDragPayload.decode(["not-a-uuid"]).isEmpty)
        #expect(BoardDragPayload.decode(["not-a-uuid,\(id.uuidString)"]) == [id])
        #expect(BoardDragPayload.decode([""]).isEmpty)
    }
}

@MainActor
struct TaskBoardMembershipTests {
    @Test func isOnBoard_followsPlanHorizon() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let task = Task(summary: "t")
        context.insert(task)

        #expect(!task.isOnBoard)
        task.place(on: .maybe)
        #expect(task.isOnBoard)
        task.place(on: nil)
        #expect(!task.isOnBoard)
    }
}
