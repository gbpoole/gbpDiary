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

    @Test func outdent_atZeroIndent_doesNothing() {
        let parent = DayEntry(kind: .note, sortOrder: 0, indentLevel: 0)
        let child = DayEntry(kind: .note, sortOrder: 1, indentLevel: 1)

        DayEntryOrdering.outdent(entry: parent, in: [parent, child])

        #expect(parent.indentLevel == 0)
        #expect(child.indentLevel == 1)
    }

    @Test func moveEntry_whenEntryNotInList_doesNothing() {
        let a = DayEntry(kind: .note, sortOrder: 0, indentLevel: 0)
        let b = DayEntry(kind: .note, sortOrder: 1, indentLevel: 1)
        let external = DayEntry(kind: .note, sortOrder: 99, indentLevel: 3)

        DayEntryOrdering.moveEntry(external, toDropIndex: 0, in: [a, b])

        #expect(a.sortOrder == 0)
        #expect(b.sortOrder == 1)
        #expect(external.sortOrder == 99)
        #expect(external.indentLevel == 3)
    }

    // MARK: - Meeting-nesting guard

    @Test func indent_meetingUnderMeeting_returnsFalseAndLeavesLevel() {
        let outer = DayEntry(kind: .meeting, sortOrder: 0, indentLevel: 0)
        let inner = DayEntry(kind: .meeting, sortOrder: 1, indentLevel: 0)

        let result = DayEntryOrdering.indent(entry: inner, in: [outer, inner])

        #expect(result == false)
        #expect(inner.indentLevel == 0)
    }

    @Test func outdent_meetingStillUnderMeeting_returnsFalseAndLeavesLevel() {
        let outer = DayEntry(kind: .meeting, sortOrder: 0, indentLevel: 0)
        let inner = DayEntry(kind: .meeting, sortOrder: 1, indentLevel: 2)

        // Outdenting from 2 → 1; level 1 still nests under outer (level 0 meeting) → blocked.
        let result = DayEntryOrdering.outdent(entry: inner, in: [outer, inner])

        #expect(result == false)
        #expect(inner.indentLevel == 2)
    }

    @Test func moveEntry_meetingDroppedUnderMeeting_returnsFalseAndKeepsOrder() {
        let note   = DayEntry(kind: .note,    sortOrder: 0, indentLevel: 0)
        let parent = DayEntry(kind: .meeting, sortOrder: 1, indentLevel: 0)
        let child  = DayEntry(kind: .note,    sortOrder: 2, indentLevel: 1)
        let dragged = DayEntry(kind: .meeting, sortOrder: 3, indentLevel: 0)

        // Dropping between parent and child infers level 1, putting dragged under parent (a meeting).
        let result = DayEntryOrdering.moveEntry(dragged, toDropIndex: 2, in: [note, parent, child, dragged])

        #expect(result == false)
        #expect(dragged.sortOrder == 3)
        #expect(dragged.indentLevel == 0)
    }

    @Test func indent_meetingUnderNote_returnsTrue() {
        let note    = DayEntry(kind: .note,    sortOrder: 0, indentLevel: 0)
        let meeting = DayEntry(kind: .meeting, sortOrder: 1, indentLevel: 0)

        let result = DayEntryOrdering.indent(entry: meeting, in: [note, meeting])

        #expect(result == true)
        #expect(meeting.indentLevel == 1)
    }
}

// MARK: - Note merge tests

@MainActor
struct DayEntryMergeTests {
    @Test func mergeAdjacentNotes_twoAdjacentNotes_mergesText() {
        let a = DayEntry(kind: .note, text: "Hello", sortOrder: 0, indentLevel: 0)
        let b = DayEntry(kind: .note, text: "World", sortOrder: 1, indentLevel: 0)

        let (redirectMap, toDelete) = DayEntryOrdering.mergeAdjacentNotes(in: [a, b])

        #expect(a.text == "Hello\n\nWorld")
        #expect(toDelete.count == 1)
        #expect(toDelete.first?.id == b.id)
        #expect(redirectMap[b.id]?.id == a.id)
    }

    @Test func mergeAdjacentNotes_notesSeparatedByTask_notMerged() {
        let a = DayEntry(kind: .note, text: "Hello", sortOrder: 0, indentLevel: 0)
        let t = DayEntry(kind: .task, sortOrder: 1, indentLevel: 0)
        let b = DayEntry(kind: .note, text: "World", sortOrder: 2, indentLevel: 0)

        let (redirectMap, toDelete) = DayEntryOrdering.mergeAdjacentNotes(in: [a, t, b])

        #expect(a.text == "Hello")
        #expect(b.text == "World")
        #expect(toDelete.isEmpty)
        #expect(redirectMap.isEmpty)
    }

    @Test func mergeAdjacentNotes_emptyNote_notMerged() {
        let a = DayEntry(kind: .note, text: "", sortOrder: 0, indentLevel: 0)
        let b = DayEntry(kind: .note, text: "World", sortOrder: 1, indentLevel: 0)

        let (redirectMap, toDelete) = DayEntryOrdering.mergeAdjacentNotes(in: [a, b])

        #expect(a.text == "")
        #expect(b.text == "World")
        #expect(toDelete.isEmpty)
        #expect(redirectMap.isEmpty)
    }

    @Test func mergeAdjacentNotes_threeAdjacentNotes_chainsAll() {
        let a = DayEntry(kind: .note, text: "A", sortOrder: 0, indentLevel: 0)
        let b = DayEntry(kind: .note, text: "B", sortOrder: 1, indentLevel: 0)
        let c = DayEntry(kind: .note, text: "C", sortOrder: 2, indentLevel: 0)

        let (redirectMap, toDelete) = DayEntryOrdering.mergeAdjacentNotes(in: [a, b, c])

        #expect(a.text == "A\n\nB\n\nC")
        #expect(toDelete.count == 2)
        #expect(redirectMap[b.id]?.id == a.id)
        #expect(redirectMap[c.id]?.id == a.id)
    }
}
