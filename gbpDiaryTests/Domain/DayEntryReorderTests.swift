import Testing
@testable import gbpDiary

@MainActor
struct DayEntryReorderTests {
    @Test func moveEntry_reordersAndInfersIndent() {
        let a = DayEntry(kind: .note, sortOrder: 0, indentLevel: 0)
        let b = DayEntry(kind: .note, sortOrder: 1, indentLevel: 2)
        let c = DayEntry(kind: .note, sortOrder: 2, indentLevel: 1)

        DayEntryOrdering.moveEntry(c, toDropIndex: 1, in: [a, b, c])

        #expect(a.sortOrder == 0)
        #expect(c.sortOrder == 1)
        #expect(b.sortOrder == 2)
        #expect(c.indentLevel == 2)
    }

    @Test func indent_increasesSubtreeWithClamp() {
        let parent = DayEntry(kind: .note, sortOrder: 0, indentLevel: 5)
        let child = DayEntry(kind: .note, sortOrder: 1, indentLevel: 6)
        let sibling = DayEntry(kind: .note, sortOrder: 2, indentLevel: 5)

        DayEntryOrdering.indent(entry: parent, in: [parent, child, sibling])

        #expect(parent.indentLevel == 6)
        #expect(child.indentLevel == 6)
        #expect(sibling.indentLevel == 5)
    }

    @Test func outdent_decreasesSubtreeWithoutGoingNegative() {
        let parent = DayEntry(kind: .note, sortOrder: 0, indentLevel: 1)
        let child = DayEntry(kind: .note, sortOrder: 1, indentLevel: 2)
        let sibling = DayEntry(kind: .note, sortOrder: 2, indentLevel: 1)

        DayEntryOrdering.outdent(entry: parent, in: [parent, child, sibling])

        #expect(parent.indentLevel == 0)
        #expect(child.indentLevel == 1)
        #expect(sibling.indentLevel == 1)
    }

    @Test func moveEntry_movingDownAdjustsTargetIndexAndSortOrder() {
        let a = DayEntry(kind: .note, sortOrder: 0, indentLevel: 0)
        let b = DayEntry(kind: .note, sortOrder: 1, indentLevel: 1)
        let c = DayEntry(kind: .note, sortOrder: 2, indentLevel: 1)
        let d = DayEntry(kind: .note, sortOrder: 3, indentLevel: 0)

        DayEntryOrdering.moveEntry(b, toDropIndex: 4, in: [a, b, c, d])

        #expect(a.sortOrder == 0)
        #expect(c.sortOrder == 1)
        #expect(d.sortOrder == 2)
        #expect(b.sortOrder == 3)
        #expect(b.indentLevel == 0)
    }
}
