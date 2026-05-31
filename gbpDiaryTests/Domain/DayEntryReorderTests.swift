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

    @Test func absorbMeetingTasks_sweepsChildTaskDayEntries_andSetsOriginMinutes() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let (mtgEntry, minutes) = meetingEntry(sortOrder: 0, indentLevel: 0, context: context)
        let (parentEntry, parentTask) = taskEntry(summary: "parent", sortOrder: 1, indentLevel: 1, context: context)
        let (childEntry, childTask) = taskEntry(summary: "child", sortOrder: 2, indentLevel: 2, context: context)
        childTask.parent = parentTask  // pre-set by reconcileTaskParents in production

        let toDelete = DayEntryOrdering.absorbMeetingTasks(in: [mtgEntry, parentEntry, childEntry])

        #expect(parentTask.originMinutes?.id == minutes.id)
        #expect(parentTask.meetingTaskSortOrder == 0)
        #expect(childTask.originMinutes?.id == minutes.id)
        #expect(toDelete.count == 2)
        #expect(toDelete.contains(where: { $0.id == parentEntry.id }))
        #expect(toDelete.contains(where: { $0.id == childEntry.id }))
    }

    @Test func absorbMeetingTasks_deepSubtree_allDayEntriesCollected() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let (mtgEntry, minutes) = meetingEntry(sortOrder: 0, indentLevel: 0, context: context)
        let (e1, t1) = taskEntry(summary: "A", sortOrder: 1, indentLevel: 1, context: context)
        let (e2, t2) = taskEntry(summary: "B", sortOrder: 2, indentLevel: 2, context: context)
        let (e3, t3) = taskEntry(summary: "C", sortOrder: 3, indentLevel: 3, context: context)
        t2.parent = t1
        t3.parent = t2

        let toDelete = DayEntryOrdering.absorbMeetingTasks(in: [mtgEntry, e1, e2, e3])

        #expect(t1.originMinutes?.id == minutes.id)
        #expect(t2.originMinutes?.id == minutes.id)
        #expect(t3.originMinutes?.id == minutes.id)
        #expect(t1.meetingTaskSortOrder == 0)
        #expect(toDelete.count == 3)
    }
}

// MARK: - reconcileTaskParents tests

@MainActor
struct ReconcileTaskParentTests {
    private func makeTask(summary: String = "T", context: ModelContext) -> Task {
        let t = Task(summary: summary); context.insert(t); return t
    }

    private func makeTaskEntry(_ task: Task, sortOrder: Int, indentLevel: Int,
                               context: ModelContext) -> DayEntry {
        let e = DayEntry(kind: .task, sortOrder: sortOrder, indentLevel: indentLevel)
        e.task = task; context.insert(e); return e
    }

    private func makeNoteEntry(sortOrder: Int, indentLevel: Int, context: ModelContext) -> DayEntry {
        let e = DayEntry(kind: .note, sortOrder: sortOrder, indentLevel: indentLevel)
        context.insert(e); return e
    }

    private func makeMeetingEntry(sortOrder: Int, indentLevel: Int, context: ModelContext) -> DayEntry {
        let e = DayEntry(kind: .meeting, sortOrder: sortOrder, indentLevel: indentLevel)
        context.insert(e); return e
    }

    @Test func reconcile_topLevelTask_parentIsNil() throws {
        let container = try TestModelContainer.make()
        let ctx = ModelContext(container)
        let t = makeTask(context: ctx)
        let e = makeTaskEntry(t, sortOrder: 0, indentLevel: 0, context: ctx)
        DayEntryOrdering.reconcileTaskParents(in: [e])
        #expect(t.parent == nil)
    }

    @Test func reconcile_indentedUnderTask_parentSet() throws {
        let container = try TestModelContainer.make()
        let ctx = ModelContext(container)
        let tA = makeTask(summary: "A", context: ctx)
        let tB = makeTask(summary: "B", context: ctx)
        let eA = makeTaskEntry(tA, sortOrder: 0, indentLevel: 0, context: ctx)
        let eB = makeTaskEntry(tB, sortOrder: 1, indentLevel: 1, context: ctx)
        DayEntryOrdering.reconcileTaskParents(in: [eA, eB])
        #expect(tB.parent?.id == tA.id)
    }

    @Test func reconcile_indentedUnderNote_parentIsNil() throws {
        let container = try TestModelContainer.make()
        let ctx = ModelContext(container)
        let tB = makeTask(summary: "B", context: ctx)
        let note = makeNoteEntry(sortOrder: 0, indentLevel: 0, context: ctx)
        let eB = makeTaskEntry(tB, sortOrder: 1, indentLevel: 1, context: ctx)
        DayEntryOrdering.reconcileTaskParents(in: [note, eB])
        #expect(tB.parent == nil)
    }

    @Test func reconcile_indentedUnderMeeting_parentIsNil() throws {
        let container = try TestModelContainer.make()
        let ctx = ModelContext(container)
        let tB = makeTask(summary: "B", context: ctx)
        let mtg = makeMeetingEntry(sortOrder: 0, indentLevel: 0, context: ctx)
        let eB = makeTaskEntry(tB, sortOrder: 1, indentLevel: 1, context: ctx)
        DayEntryOrdering.reconcileTaskParents(in: [mtg, eB])
        #expect(tB.parent == nil)
    }

    @Test func reconcile_deepHierarchy_threeLevel() throws {
        let container = try TestModelContainer.make()
        let ctx = ModelContext(container)
        let tA = makeTask(summary: "A", context: ctx)
        let tB = makeTask(summary: "B", context: ctx)
        let tC = makeTask(summary: "C", context: ctx)
        let eA = makeTaskEntry(tA, sortOrder: 0, indentLevel: 0, context: ctx)
        let eB = makeTaskEntry(tB, sortOrder: 1, indentLevel: 1, context: ctx)
        let eC = makeTaskEntry(tC, sortOrder: 2, indentLevel: 2, context: ctx)
        DayEntryOrdering.reconcileTaskParents(in: [eA, eB, eC])
        #expect(tB.parent?.id == tA.id)
        #expect(tC.parent?.id == tB.id)
    }

    @Test func reconcile_reparentsAfterReorder() throws {
        let container = try TestModelContainer.make()
        let ctx = ModelContext(container)
        let tA = makeTask(summary: "A", context: ctx)
        let tB = makeTask(summary: "B", context: ctx)
        let tC = makeTask(summary: "C", context: ctx)
        let eA = makeTaskEntry(tA, sortOrder: 0, indentLevel: 0, context: ctx)
        let eB = makeTaskEntry(tB, sortOrder: 1, indentLevel: 1, context: ctx)
        let eC = makeTaskEntry(tC, sortOrder: 2, indentLevel: 1, context: ctx)
        DayEntryOrdering.reconcileTaskParents(in: [eA, eB, eC])
        #expect(tB.parent?.id == tA.id)
        #expect(tC.parent?.id == tA.id)
        // Move eB after eC — C is still child of A
        eB.sortOrder = 3
        DayEntryOrdering.reconcileTaskParents(in: [eA, eB, eC])
        #expect(tC.parent?.id == tA.id)
        #expect(tB.parent?.id == tA.id)
    }
}

// MARK: - materializeChildDayEntries tests

@MainActor
struct MaterializeChildDayEntriesTests {
    @Test func materialize_singleChild_createsDayEntryAtLevelPlusOne() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let record = DayRecord(date: .now)
        context.insert(record)
        let parent = Task(summary: "parent"); context.insert(parent)
        let child = Task(summary: "child"); context.insert(child)
        child.parent = parent

        DayEntryOrdering.materializeChildDayEntries(
            of: parent, atLevel: 1, insertingAt: 5, in: record, context: context)

        let childEntries = record.entries.filter { $0.task?.id == child.id }
        #expect(childEntries.count == 1)
        #expect(childEntries.first?.indentLevel == 1)
        #expect(childEntries.first?.sortOrder == 5)
    }

    @Test func materialize_deepTree_DFSOrder_correctLevels() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let record = DayRecord(date: .now)
        context.insert(record)
        let parent = Task(summary: "parent"); context.insert(parent)
        let child1 = Task(summary: "child1"); context.insert(child1); child1.parent = parent
        let child2 = Task(summary: "child2"); context.insert(child2); child2.parent = parent
        let grandchild = Task(summary: "grandchild"); context.insert(grandchild); grandchild.parent = child1

        DayEntryOrdering.materializeChildDayEntries(
            of: parent, atLevel: 1, insertingAt: 0, in: record, context: context)

        let entries = record.entries.sorted { $0.sortOrder < $1.sortOrder }
        #expect(entries.count == 3)
        // DFS: child1, grandchild, child2
        #expect(entries[0].task?.summary == "child1")
        #expect(entries[0].indentLevel == 1)
        #expect(entries[1].task?.summary == "grandchild")
        #expect(entries[1].indentLevel == 2)
        #expect(entries[2].task?.summary == "child2")
        #expect(entries[2].indentLevel == 1)
    }

    @Test func materialize_shiftsExistingEntries() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let record = DayRecord(date: .now)
        context.insert(record)
        // Pre-existing entry at sortOrder 0
        let existing = DayEntry(kind: .note, sortOrder: 0, indentLevel: 0)
        existing.dayRecord = record
        context.insert(existing)
        let parent = Task(summary: "P"); context.insert(parent)
        let child = Task(summary: "C"); context.insert(child); child.parent = parent

        DayEntryOrdering.materializeChildDayEntries(
            of: parent, atLevel: 1, insertingAt: 0, in: record, context: context)

        #expect(existing.sortOrder == 1)  // shifted by 1
        let childEntry = record.entries.first(where: { $0.task?.id == child.id })
        #expect(childEntry?.sortOrder == 0)
    }

    @Test func materialize_emptyChildren_noOp() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let record = DayRecord(date: .now)
        context.insert(record)
        let parent = Task(summary: "leaf"); context.insert(parent)

        let result = DayEntryOrdering.materializeChildDayEntries(
            of: parent, atLevel: 1, insertingAt: 0, in: record, context: context)

        #expect(record.entries.isEmpty)
        #expect(result == 0)
    }
}
