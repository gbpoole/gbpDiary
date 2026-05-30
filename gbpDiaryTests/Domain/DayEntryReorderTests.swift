import Foundation
import Testing
import SwiftData
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

    @Test func moveEntry_dropAfterMeeting_infersChildLevel() {
        let meeting = DayEntry(kind: .meeting, sortOrder: 0, indentLevel: 0)
        let note    = DayEntry(kind: .note,    sortOrder: 1, indentLevel: 0)
        let task    = DayEntry(kind: .task,    sortOrder: 2, indentLevel: 0)

        // Drop task at index 1 — right after the meeting, before note.
        DayEntryOrdering.moveEntry(task, toDropIndex: 1, in: [meeting, note, task])

        #expect(task.indentLevel == 1)  // bumped to meeting+1, not 0
        #expect(task.sortOrder == 1)
        #expect(meeting.sortOrder == 0)
        #expect(note.sortOrder == 2)
    }

    @Test func moveEntry_dropAfterMeetingWithDeeperFollower_usesNaturalInference() {
        // When the next entry is already deeper than the meeting, natural inference
        // already produces the right level; the meeting bump should not double-apply.
        let meeting = DayEntry(kind: .meeting, sortOrder: 0, indentLevel: 0)
        let child   = DayEntry(kind: .note,    sortOrder: 1, indentLevel: 1)
        let task    = DayEntry(kind: .task,    sortOrder: 2, indentLevel: 0)

        DayEntryOrdering.moveEntry(task, toDropIndex: 1, in: [meeting, child, task])

        #expect(task.indentLevel == 1)  // natural inference: max(0,1)=1, bump condition false
    }

    @Test func moveEntry_dropMeetingAfterMeeting_keepsSiblingLevel() {
        // Dragging a meeting to sit right after another meeting must NOT trigger the
        // indent bump — both meetings should stay at the same level so they can be
        // reordered as siblings. The nesting guard would block a bumped meeting anyway,
        // but the bump itself is the part that must be absent.
        let meeting1 = DayEntry(kind: .meeting, sortOrder: 0, indentLevel: 0)
        let note     = DayEntry(kind: .note,    sortOrder: 1, indentLevel: 0)
        let meeting2 = DayEntry(kind: .meeting, sortOrder: 2, indentLevel: 0)

        // Drop meeting2 at index 1 — right after meeting1.
        let result = DayEntryOrdering.moveEntry(meeting2, toDropIndex: 1, in: [meeting1, note, meeting2])

        #expect(result == true)              // not blocked by nesting guard
        #expect(meeting2.indentLevel == 0)  // stays sibling, not bumped to 1
        #expect(meeting2.sortOrder == 1)
        #expect(meeting1.sortOrder == 0)
        #expect(note.sortOrder == 2)
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

// MARK: - notesId tests

@MainActor
struct NotesIdTests {
    @Test func notesId_isNotEqualToSourceId() {
        let id = UUID()
        #expect(notesId(for: id) != id)
    }

    @Test func notesId_isDeterministic() {
        let id = UUID()
        #expect(notesId(for: id) == notesId(for: id))
    }

    @Test func notesId_isOwnInverse() {
        let id = UUID()
        #expect(notesId(for: notesId(for: id)) == id)
    }

    @Test func notesId_noCollisionBetweenTwoDifferentEntries() {
        let a = UUID(), b = UUID()
        #expect(notesId(for: a) != notesId(for: b))
        #expect(notesId(for: a) != b)
        #expect(notesId(for: b) != a)
    }
}

// MARK: - Absorption tests

@MainActor
struct DayEntryAbsorptionTests {
    // Helper: create a task-backed DayEntry with a linked Task inserted into context.
    private func taskEntry(notes: String? = nil, sortOrder: Int, indentLevel: Int = 0,
                           context: ModelContext) -> (DayEntry, Task) {
        let task = Task(summary: "T")
        task.notes = notes
        context.insert(task)
        let entry = DayEntry(kind: .task, sortOrder: sortOrder, indentLevel: indentLevel)
        entry.task = task
        context.insert(entry)
        return (entry, task)
    }

    // Helper: create a meeting-backed DayEntry with a linked Minutes inserted into context.
    private func meetingEntry(content: String? = nil, sortOrder: Int, indentLevel: Int = 0,
                              context: ModelContext) -> (DayEntry, Minutes) {
        let minutes = Minutes(meetingAt: .now)
        minutes.minutesContent = content
        context.insert(minutes)
        let entry = DayEntry(kind: .meeting, sortOrder: sortOrder, indentLevel: indentLevel)
        entry.minutes = minutes
        context.insert(entry)
        return (entry, minutes)
    }

    @Test func absorb_noteAtIndentPlusOneAfterTask_absorbsIntoNotes() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let (taskEntry, task) = taskEntry(sortOrder: 0, context: context)
        let note = DayEntry(kind: .note, text: "hello", sortOrder: 1, indentLevel: 1)
        context.insert(note)
        let (_, toDelete) = DayEntryOrdering.absorbAdjacentNotes(in: [taskEntry, note])
        #expect(task.notes == "hello")
        #expect(toDelete.count == 1)
        #expect(toDelete.first?.id == note.id)
    }

    @Test func absorb_noteAtIndentPlusOneAfterMeeting_absorbsIntoMinutes() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let (mtgEntry, minutes) = meetingEntry(sortOrder: 0, context: context)
        let note = DayEntry(kind: .note, text: "agenda item", sortOrder: 1, indentLevel: 1)
        context.insert(note)
        let (_, toDelete) = DayEntryOrdering.absorbAdjacentNotes(in: [mtgEntry, note])
        #expect(minutes.minutesContent == "agenda item")
        #expect(toDelete.count == 1)
    }

    @Test func absorb_appendsToExistingNotes() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let (taskEntry, task) = taskEntry(notes: "existing", sortOrder: 0, context: context)
        let note = DayEntry(kind: .note, text: "new", sortOrder: 1, indentLevel: 1)
        context.insert(note)
        DayEntryOrdering.absorbAdjacentNotes(in: [taskEntry, note])
        #expect(task.notes == "existing\n\nnew")
    }

    @Test func absorb_emptyNote_skipped() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let (taskEntry, task) = taskEntry(sortOrder: 0, context: context)
        let note = DayEntry(kind: .note, text: "", sortOrder: 1, indentLevel: 1)
        context.insert(note)
        let (_, toDelete) = DayEntryOrdering.absorbAdjacentNotes(in: [taskEntry, note])
        #expect(task.notes == nil)
        #expect(toDelete.isEmpty)
    }

    @Test func absorb_noteAtSameLevelAsTask_notAbsorbed() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let (taskEntry, task) = taskEntry(sortOrder: 0, indentLevel: 0, context: context)
        let note = DayEntry(kind: .note, text: "sibling", sortOrder: 1, indentLevel: 0)
        context.insert(note)
        let (_, toDelete) = DayEntryOrdering.absorbAdjacentNotes(in: [taskEntry, note])
        #expect(task.notes == nil)
        #expect(toDelete.isEmpty)
    }

    @Test func absorb_noteAtLevelPlusTwoAfterTask_notAbsorbed() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let (taskEntry, task) = taskEntry(sortOrder: 0, indentLevel: 0, context: context)
        let note = DayEntry(kind: .note, text: "deep", sortOrder: 1, indentLevel: 2)
        context.insert(note)
        let (_, toDelete) = DayEntryOrdering.absorbAdjacentNotes(in: [taskEntry, note])
        #expect(task.notes == nil)
        #expect(toDelete.isEmpty)
    }

    @Test func absorb_consecutiveNotesAtIndentPlusOne_bothAbsorbed() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let (taskEntry, task) = taskEntry(sortOrder: 0, context: context)
        let n1 = DayEntry(kind: .note, text: "first", sortOrder: 1, indentLevel: 1)
        let n2 = DayEntry(kind: .note, text: "second", sortOrder: 2, indentLevel: 1)
        context.insert(n1); context.insert(n2)
        let (_, toDelete) = DayEntryOrdering.absorbAdjacentNotes(in: [taskEntry, n1, n2])
        #expect(task.notes == "first\n\nsecond")
        #expect(toDelete.count == 2)
    }

    @Test func absorb_noteAfterNote_notAbsorbed() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let a = DayEntry(kind: .note, text: "A", sortOrder: 0, indentLevel: 0)
        let b = DayEntry(kind: .note, text: "B", sortOrder: 1, indentLevel: 0)
        context.insert(a); context.insert(b)
        let (_, toDelete) = DayEntryOrdering.absorbAdjacentNotes(in: [a, b])
        #expect(toDelete.isEmpty)
    }

    @Test func absorb_orphanedTaskEntry_noteNotDeleted() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        // task entry with no linked Task (orphaned)
        let orphan = DayEntry(kind: .task, sortOrder: 0, indentLevel: 0)
        context.insert(orphan)
        let note = DayEntry(kind: .note, text: "stranded", sortOrder: 1, indentLevel: 1)
        context.insert(note)
        let (_, toDelete) = DayEntryOrdering.absorbAdjacentNotes(in: [orphan, note])
        #expect(toDelete.isEmpty)
    }

    // mergeAdjacentNotes has no indent-level guard — it would merge note@1 with note@0 if run
    // first, pulling unrelated plain-note text into task.notes. Absorption must run first so the
    // indented note is consumed before merge can join it to its sibling.
    @Test func absorbBeforeMerge_plainSiblingNoteNotPulledIntoTaskNotes() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let (taskEntry, task) = taskEntry(sortOrder: 0, context: context)
        let indented = DayEntry(kind: .note, text: "task-note", sortOrder: 1, indentLevel: 1)
        let sibling  = DayEntry(kind: .note, text: "plain-note", sortOrder: 2, indentLevel: 0)
        context.insert(indented); context.insert(sibling)
        let entries = [taskEntry, indented, sibling]

        let (_, absorbDelete) = DayEntryOrdering.absorbAdjacentNotes(in: entries)
        let remaining = entries.filter { e in !absorbDelete.contains(where: { $0.id == e.id }) }
        DayEntryOrdering.mergeAdjacentNotes(in: remaining)

        #expect(task.notes == "task-note")
        #expect(sibling.text == "plain-note")
        #expect(absorbDelete.count == 1)
        #expect(absorbDelete.first?.id == indented.id)
    }
}

// MARK: - Meeting task absorption tests

@MainActor
struct MeetingTaskAbsorptionTests {
    private func meetingEntry(sortOrder: Int, indentLevel: Int = 0,
                              context: ModelContext) -> (DayEntry, Minutes) {
        let minutes = Minutes(meetingAt: .now)
        context.insert(minutes)
        let entry = DayEntry(kind: .meeting, sortOrder: sortOrder, indentLevel: indentLevel)
        entry.minutes = minutes
        context.insert(entry)
        return (entry, minutes)
    }

    private func taskEntry(summary: String = "T", sortOrder: Int, indentLevel: Int,
                           context: ModelContext) -> (DayEntry, Task) {
        let task = Task(summary: summary)
        context.insert(task)
        let entry = DayEntry(kind: .task, sortOrder: sortOrder, indentLevel: indentLevel)
        entry.task = task
        context.insert(entry)
        return (entry, task)
    }

    @Test func absorbMeetingTasks_singleTaskAtIndentPlusOne_linksToNewTasks() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let (mtgEntry, minutes) = meetingEntry(sortOrder: 0, context: context)
        let (taskEntry, task) = taskEntry(summary: "action", sortOrder: 1, indentLevel: 1, context: context)

        let toDelete = DayEntryOrdering.absorbMeetingTasks(in: [mtgEntry, taskEntry])

        #expect(task.originMinutes?.id == minutes.id)
        #expect(task.meetingTaskSortOrder == 0)
        #expect(toDelete.count == 1)
        #expect(toDelete.first?.id == taskEntry.id)
    }

    @Test func absorbMeetingTasks_consecutiveTasks_allAbsorbedInOrder() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let (mtgEntry, minutes) = meetingEntry(sortOrder: 0, context: context)
        let (te1, t1) = taskEntry(summary: "first",  sortOrder: 1, indentLevel: 1, context: context)
        let (te2, t2) = taskEntry(summary: "second", sortOrder: 2, indentLevel: 1, context: context)

        let toDelete = DayEntryOrdering.absorbMeetingTasks(in: [mtgEntry, te1, te2])

        #expect(t1.originMinutes?.id == minutes.id)
        #expect(t2.originMinutes?.id == minutes.id)
        #expect(t1.meetingTaskSortOrder == 0)
        #expect(t2.meetingTaskSortOrder == 1)
        #expect(toDelete.count == 2)
    }

    @Test func absorbMeetingTasks_taskAtSameLevel_notAbsorbed() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let (mtgEntry, _) = meetingEntry(sortOrder: 0, context: context)
        let (taskEntry, task) = taskEntry(summary: "sibling", sortOrder: 1, indentLevel: 0, context: context)

        let toDelete = DayEntryOrdering.absorbMeetingTasks(in: [mtgEntry, taskEntry])

        #expect(task.originMinutes == nil)
        #expect(toDelete.isEmpty)
    }

    @Test func absorbMeetingTasks_noteBlocksTask_taskNotAbsorbed() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let (mtgEntry, _) = meetingEntry(sortOrder: 0, context: context)
        let note = DayEntry(kind: .note, text: "minutes", sortOrder: 1, indentLevel: 1)
        let (taskEntry, task) = taskEntry(summary: "action", sortOrder: 2, indentLevel: 1, context: context)
        context.insert(note)

        let toDelete = DayEntryOrdering.absorbMeetingTasks(in: [mtgEntry, note, taskEntry])

        #expect(task.originMinutes == nil)
        #expect(toDelete.isEmpty)
    }

    @Test func absorbMeetingTasks_orphanedMeetingEntry_taskNotAbsorbed() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let orphan = DayEntry(kind: .meeting, sortOrder: 0, indentLevel: 0)
        context.insert(orphan)
        let (taskEntry, task) = taskEntry(summary: "action", sortOrder: 1, indentLevel: 1, context: context)

        let toDelete = DayEntryOrdering.absorbMeetingTasks(in: [orphan, taskEntry])

        #expect(task.originMinutes == nil)
        #expect(toDelete.isEmpty)
    }

    @Test func absorbMeetingTasks_orphanedTaskEntry_notAbsorbed() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let (mtgEntry, _) = meetingEntry(sortOrder: 0, context: context)
        let orphan = DayEntry(kind: .task, sortOrder: 1, indentLevel: 1)
        context.insert(orphan)

        let toDelete = DayEntryOrdering.absorbMeetingTasks(in: [mtgEntry, orphan])

        #expect(toDelete.isEmpty)
    }

    @Test func absorbMeetingTasks_appendsAfterExistingTasks() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let (mtgEntry, minutes) = meetingEntry(sortOrder: 0, context: context)
        // Seed an existing task in the meeting's newTasks list
        let existing = Task(summary: "existing")
        existing.originMinutes = minutes
        existing.meetingTaskSortOrder = 5
        context.insert(existing)
        let (taskEntry, newTask) = taskEntry(summary: "new", sortOrder: 1, indentLevel: 1, context: context)

        DayEntryOrdering.absorbMeetingTasks(in: [mtgEntry, taskEntry])

        #expect(newTask.meetingTaskSortOrder == 6)
    }
}
