import Testing
import Foundation
@testable import gbpDiary

@Suite("TaskSelectionReconcile")
struct TaskSelectionReconcileTests {
    private let a = UUID(), b = UUID(), c = UUID(), d = UUID()

    @Test func hiddenSelection_movesToStashed() {
        let r = TaskSelectionReconcile.reconcile(selection: [a, b], stashed: [], visible: [a])
        #expect(r.selection == [a])   // b left the visible set
        #expect(r.stashed == [b])
    }

    @Test func stashedReappearing_restoresToSelection() {
        let r = TaskSelectionReconcile.reconcile(selection: [a], stashed: [b], visible: [a, b])
        #expect(r.selection == [a, b])
        #expect(r.stashed.isEmpty)
    }

    @Test func hideAndRestore_simultaneously() {
        // b becomes hidden while stashed c reappears in the same reconcile.
        let r = TaskSelectionReconcile.reconcile(selection: [a, b], stashed: [c], visible: [a, c])
        #expect(r.selection == [a, c])
        #expect(r.stashed == [b])
    }

    @Test func allVisible_isNoOp() {
        let r = TaskSelectionReconcile.reconcile(selection: [a, b], stashed: [], visible: [a, b, c, d])
        #expect(r.selection == [a, b])
        #expect(r.stashed.isEmpty)
    }

    @Test func empty_returnsEmpty() {
        let r = TaskSelectionReconcile.reconcile(selection: [], stashed: [], visible: [a, b])
        #expect(r.selection.isEmpty)
        #expect(r.stashed.isEmpty)
    }
}
