import Foundation
import Testing
@testable import gbpDiary

struct TabReorderTests {
    private let a = UUID(), b = UUID(), c = UUID(), d = UUID()
    private var order: [UUID] { [a, b, c, d] }

    @Test func move_rightward_landsBeforeTarget() {
        // Drag A onto C → A inserts immediately before C.
        #expect(TabReorder.move(order, id: a, toIndex: 2) == [b, a, c, d])
    }

    @Test func move_leftward_landsBeforeTarget() {
        // Drag D onto B → D inserts immediately before B.
        #expect(TabReorder.move(order, id: d, toIndex: 1) == [a, d, b, c])
    }

    @Test func move_toEnd_appends() {
        #expect(TabReorder.move(order, id: a, toIndex: 4) == [b, c, d, a])
    }

    @Test func move_toStart() {
        #expect(TabReorder.move(order, id: c, toIndex: 0) == [c, a, b, d])
    }

    @Test func move_ontoSelf_isNoOp() {
        #expect(TabReorder.move(order, id: b, toIndex: 1) == order)
    }

    @Test func move_unknownId_returnsUnchanged() {
        #expect(TabReorder.move(order, id: UUID(), toIndex: 2) == order)
    }

    @Test func move_indexBeyondBounds_clampsToEnd() {
        #expect(TabReorder.move(order, id: a, toIndex: 99) == [b, c, d, a])
    }
}
