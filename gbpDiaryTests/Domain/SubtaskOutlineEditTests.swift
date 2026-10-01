import Testing
import Foundation
@testable import gbpDiary

@Suite("SubtaskOutlineEdit")
struct SubtaskOutlineEditTests {

    // A small fixed tree, built with readable ids:
    //   a (0)
    //   b (1)
    //     c (0)
    //     d (1)
    //       e (0)
    //   f (2)
    private let a = UUID(), b = UUID(), c = UUID(), d = UUID(), e = UUID(), f = UUID()
    private let root = UUID()        // the surface's own task (the floor on a task page)

    private var rows: [OutlineRow] {
        [OutlineRow(id: a, parentID: root, sortOrder: 0),
         OutlineRow(id: b, parentID: root, sortOrder: 1),
         OutlineRow(id: c, parentID: b, sortOrder: 0),
         OutlineRow(id: d, parentID: b, sortOrder: 1),
         OutlineRow(id: e, parentID: d, sortOrder: 0),
         OutlineRow(id: f, parentID: root, sortOrder: 2)]
    }

    // MARK: - Tab

    @Test func indent_becomesChildOfThePrecedingSibling() {
        #expect(SubtaskOutlineEdit.indent(b, in: rows) == .to(a))
        #expect(SubtaskOutlineEdit.indent(f, in: rows) == .to(b))
        #expect(SubtaskOutlineEdit.indent(d, in: rows) == .to(c), "nested levels work the same way")
    }

    /// The first row at any level has nothing to indent under — including the first row overall.
    @Test func indent_firstOfItsLevel_isANoOp() {
        #expect(SubtaskOutlineEdit.indent(a, in: rows) == Reparent.none)
        #expect(SubtaskOutlineEdit.indent(c, in: rows) == Reparent.none)
        #expect(SubtaskOutlineEdit.indent(e, in: rows) == Reparent.none)
    }

    @Test func indent_unknownRow_isANoOp() {
        #expect(SubtaskOutlineEdit.indent(UUID(), in: rows) == Reparent.none)
    }

    /// Order comes from `sortOrder`, not from where a row happens to sit in the array.
    @Test func indent_usesSortOrderNotArrayOrder() {
        let x = UUID(), y = UUID()
        let shuffled = [OutlineRow(id: y, parentID: root, sortOrder: 5),
                        OutlineRow(id: x, parentID: root, sortOrder: 1)]
        #expect(SubtaskOutlineEdit.indent(y, in: shuffled) == .to(x))
        #expect(SubtaskOutlineEdit.indent(x, in: shuffled) == Reparent.none)
    }

    /// Equal sort orders fall back to input order, so the result is total and never flickers.
    @Test func indent_tiedSortOrders_fallBackToInputOrder() {
        let x = UUID(), y = UUID()
        let tied = [OutlineRow(id: x, parentID: root, sortOrder: 0),
                    OutlineRow(id: y, parentID: root, sortOrder: 0)]
        #expect(SubtaskOutlineEdit.indent(y, in: tied) == .to(x))
        #expect(SubtaskOutlineEdit.indent(x, in: tied) == Reparent.none)
    }

    // MARK: - Shift-Tab

    @Test func outdent_promotesToTheGrandparent() {
        #expect(SubtaskOutlineEdit.outdent(c, in: rows, floorParentID: root) == .to(root))
        #expect(SubtaskOutlineEdit.outdent(e, in: rows, floorParentID: root) == .to(b))
    }

    /// The surface's root is a floor: a direct child can never be promoted out of the subtree on screen.
    @Test func outdent_atTheFloor_isANoOp() {
        #expect(SubtaskOutlineEdit.outdent(a, in: rows, floorParentID: root) == Reparent.none)
        #expect(SubtaskOutlineEdit.outdent(b, in: rows, floorParentID: root) == Reparent.none)
    }

    /// Curation's rows are already top-level (`parentID == nil`), so its floor is nil.
    @Test func outdent_nilFloor_treatsRootRowsAsTheFloor() {
        let x = UUID(), y = UUID()
        let flat = [OutlineRow(id: x, parentID: nil, sortOrder: 0),
                    OutlineRow(id: y, parentID: x, sortOrder: 0)]
        #expect(SubtaskOutlineEdit.outdent(x, in: flat, floorParentID: nil) == Reparent.none)
        #expect(SubtaskOutlineEdit.outdent(y, in: flat, floorParentID: nil) == .to(nil))
    }

    /// Defensive: a parent that isn't on this surface means we can't see where promotion would land.
    @Test func outdent_parentNotOnThisSurface_isANoOp() {
        let orphan = UUID()
        let detached = [OutlineRow(id: orphan, parentID: UUID(), sortOrder: 0)]
        #expect(SubtaskOutlineEdit.outdent(orphan, in: detached, floorParentID: nil) == Reparent.none)
    }

    @Test func outdent_unknownRow_isANoOp() {
        #expect(SubtaskOutlineEdit.outdent(UUID(), in: rows, floorParentID: root) == Reparent.none)
    }

    // MARK: - Append position

    @Test func appendSortOrder_isMaxPlusOneAmongSiblings() {
        #expect(SubtaskOutlineEdit.appendSortOrder(parentID: root, in: rows) == 3)
        #expect(SubtaskOutlineEdit.appendSortOrder(parentID: b, in: rows) == 2)
        #expect(SubtaskOutlineEdit.appendSortOrder(parentID: e, in: rows) == 0, "no siblings yet")
    }

    /// Max + 1, not count — a gap left by a deletion must not produce a colliding order.
    @Test func appendSortOrder_ignoresGaps() {
        let x = UUID()
        let gappy = [OutlineRow(id: x, parentID: root, sortOrder: 7)]
        #expect(SubtaskOutlineEdit.appendSortOrder(parentID: root, in: gappy) == 8)
    }

    // MARK: - Placement after an anchor (Shift-Tab)

    /// A promoted row lands directly below the parent it left, not at the end of its new level.
    @Test func placeAfter_landsImmediatelyAfterTheAnchor() {
        // e is promoted out of d, into b's children (c, d) — it should sit right after d.
        let placement = SubtaskOutlineEdit.placeAfter(anchorID: d, parentID: b, moving: e, in: rows)
        #expect(placement.order == 2)
        #expect(placement.shifted.isEmpty, "c and d already hold 0 and 1")
    }

    /// Inserting in the middle renumbers the level, so nothing collides.
    @Test func placeAfter_shiftsLaterSiblingsDown() {
        // d is promoted out of b, into root's children (a, b, f) — it should sit right after b.
        let placement = SubtaskOutlineEdit.placeAfter(anchorID: b, parentID: root, moving: d, in: rows)
        #expect(placement.order == 2)
        #expect(placement.shifted == [f: 3], "f moves from 2 to 3 to make room")
    }

    /// Gappy stored orders are normalised rather than patched around.
    @Test func placeAfter_renumbersGappyLevels() {
        let x = UUID(), y = UUID(), z = UUID()
        let gappy = [OutlineRow(id: x, parentID: root, sortOrder: 0),
                     OutlineRow(id: y, parentID: root, sortOrder: 9),
                     OutlineRow(id: z, parentID: UUID(), sortOrder: 0)]
        let placement = SubtaskOutlineEdit.placeAfter(anchorID: x, parentID: root, moving: z, in: gappy)
        #expect(placement.order == 1)
        #expect(placement.shifted == [y: 2])
    }

    @Test func placeAfter_unknownAnchor_appendsInstead() {
        let placement = SubtaskOutlineEdit.placeAfter(anchorID: UUID(), parentID: b, moving: a, in: rows)
        #expect(placement.order == 2, "max sortOrder among b's children (1) + 1")
        #expect(placement.shifted.isEmpty)
    }

    // MARK: - Deletion scope

    @Test func deletionScope_leafOnly_needsNoConfirmation() {
        let scope = SubtaskOutlineEdit.deletionScope(selected: [a, f], in: rows)
        #expect(scope.directCount == 2)
        #expect(scope.descendantCount == 0)
        #expect(!scope.needsConfirmation)
        #expect(scope.ids == [a, f])
    }

    /// Selecting `b` takes c, d and e with it — the part you can't see is what the prompt exists for.
    @Test func deletionScope_countsTheWholeCascade() {
        let scope = SubtaskOutlineEdit.deletionScope(selected: [b], in: rows)
        #expect(scope.directCount == 1)
        #expect(scope.descendantCount == 3)
        #expect(scope.needsConfirmation)
        #expect(scope.ids == [b, c, d, e])
    }

    /// A selected row nested inside another selected row isn't a second deletion root — it would have
    /// gone anyway, so counting it twice would overstate the damage.
    @Test func deletionScope_nestedSelection_isNotDoubleCounted() {
        let scope = SubtaskOutlineEdit.deletionScope(selected: [b, d, e], in: rows)
        #expect(scope.directCount == 1, "only b is a deletion root")
        #expect(scope.descendantCount == 3)
        #expect(scope.ids == [b, c, d, e])
    }

    @Test func deletionScope_emptySelection_isEmpty() {
        let scope = SubtaskOutlineEdit.deletionScope(selected: [], in: rows)
        #expect(scope.directCount == 0 && scope.descendantCount == 0 && scope.ids.isEmpty)
        #expect(!scope.needsConfirmation)
    }

    @Test func deletionScope_unknownIdsAreIgnored() {
        let scope = SubtaskOutlineEdit.deletionScope(selected: [UUID()], in: rows)
        #expect(scope.directCount == 0 && scope.ids.isEmpty)
    }

    /// A cycle in the data must not hang the count.
    @Test func deletionScope_cycleTerminates() {
        let x = UUID(), y = UUID()
        let cyclic = [OutlineRow(id: x, parentID: y, sortOrder: 0),
                      OutlineRow(id: y, parentID: x, sortOrder: 0)]
        let scope = SubtaskOutlineEdit.deletionScope(selected: [x], in: cyclic)
        #expect(scope.ids == [x, y])
    }
}
